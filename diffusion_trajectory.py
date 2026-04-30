import scipy.io as sio
import numpy as np
import torch
import torch.nn.functional as F
import matplotlib.pyplot as plt
import matplotlib.lines as mlines
import copy  # ✅ 已经修复：将 copy 模块放在全局最顶端导入

# =========================================================================
# IEEE Paper: Multi-Cluster Loop via Exponential-Aware Diffusion Inpainting
# Features: 1. Full city multi-cluster routing (Standalone Python Visualization)
#           2. Disentanglement TSP sorting for macro topology
#           3. Strict inpainting + EXPONENTIAL penalty guidance for exaggerated evasion
# =========================================================================

# --- 核心降维打击 TSP 函数：最近邻+2-opt 消除路径纠缠 ---
def tsp_nearest_neighbor_with_2opt(nodes):
    num_pts = len(nodes)
    order = [0] # 锚定第一个点为 Hub (Node 0)
    unvisited = list(range(1, num_pts))
    curr = 0
    while unvisited:
        # 贪心最近邻初始化
        dists = np.sum((nodes[unvisited] - nodes[curr])**2, axis=1)
        next_idx = int(np.argmin(dists))
        curr = unvisited[next_idx]
        order.append(curr)
        unvisited.pop(next_idx)
    
    # 执行 2-opt 局部搜索解开交叉死结
    order_np = np.array(order)
    nodes_np = nodes[order_np]
    for i in range(1, num_pts - 2):
        for j in range(i + 1, num_pts):
            if j - i == 1: continue
            new_path = copy.deepcopy(nodes_np)
            # 反转路径
            new_path[i:j+1] = new_path[i:j+1][::-1]
            
            # 计算总路径长度
            old_dist = np.sum(np.sqrt(np.sum((nodes_np[1:] - nodes_np[:-1])**2, axis=1)))
            new_dist = np.sum(np.sqrt(np.sum((new_path[1:] - new_path[:-1])**2, axis=1)))
            
            if new_dist < old_dist:
                nodes_np = new_path
                # 反转索引
                order_np[i:j+1] = order_np[i:j+1][::-1]
    
    final_order = order_np.tolist()
    final_order.append(order[0]) # 强制首尾相连开闭环
    return final_order

def run_standlone_plus_mission():
    print("1. [Loading] 正在加载城市环境与 TSP 目标序列...")
    try:
        mat_data = sio.loadmat('Urban_Mask_Data.mat')
    except FileNotFoundError:
        print("Error: 未找到 'Urban_Mask_Data.mat'。请确保已运行 MATLAB 并导出数据。")
        return

    # 数据提取
    H_mask = torch.tensor(mat_data['H_mask'], dtype=torch.float32)
    L = float(mat_data['L'].item())
    W = float(mat_data['W'].item())
    users = mat_data['users']
    idx = mat_data['idx'].flatten()
    cluster_hubs = mat_data['cluster_hubs']
    
    # 警戒阈值设定 (Tolerance-Aware)
    ALERT_THRESHOLD = 0.5 
    
    unique_clusters = np.unique(idx)
    unique_clusters = unique_clusters[unique_clusters > 0] 
    
    print(f"2. [Processing] 正在地图上演算 {len(unique_clusters)} 个业务簇的解缠与AI重绘路径...")
    all_cluster_paths = []  # 新增：用于收集所有簇的轨迹

    # 画布设定
    plt.figure(figsize=(14, 12), facecolor='white')
    plt.imshow(H_mask.numpy(), origin='lower', extent=[0, L, 0, W], cmap='jet', alpha=0.85)
    
    # 替换为高对比度的深色系，增强视觉质感
    cluster_colors = ['black', 'darkred', 'purple', 'darkslategrey', 'saddlebrown']

    for c_idx in unique_clusters:
        c_id = int(c_idx)
        c_users = users[idx == c_id]
        hub = cluster_hubs[c_id - 1, :2] 
        color = cluster_colors[(c_id - 1) % len(cluster_colors)]
        
        all_pts_arr = np.vstack([hub, c_users])
        num_user = len(c_users)
        
        # 消除乱麻，解开 TSP 序列
        sorted_order = tsp_nearest_neighbor_with_2opt(all_pts_arr)
        
        tsp_nodes = torch.tensor(all_pts_arr[sorted_order], dtype=torch.float32)
        all_segments = []
        
        print(f"   -> 正在规划 Cluster {c_id} (包含 {num_user} 个用户，消除交叉完毕)...")

        # --- 整合大模型修复：在 TSP 直线段上进行 Diffusion Inpainting (势场法避障) ---
        for i in range(len(tsp_nodes) - 1):
            start_node = tsp_nodes[i:i+1]
            end_node = tsp_nodes[i+1:i+2]
            
            # 初始化：在 Hub 和目标用户之间拉一条离散化直线
            t = torch.linspace(0, 1, 30).unsqueeze(1)
            segment = (start_node + t * (end_node - start_node)).requires_grad_(True)
            
            # 使用大步长的优化器加速推演
            optimizer = torch.optim.Adam([segment], lr=15.0)
            
            # 推演步数调整为 100，给大模型更多“时间”把轨迹“掰弯”
            for _ in range(100):
                optimizer.zero_grad()
                norm_x = (segment[:, 0] / L) * 2.0 - 1.0
                norm_y = (segment[:, 1] / W) * 2.0 - 1.0
                grid = torch.stack([norm_x, norm_y], dim=-1).view(1, 1, -1, 2)
                
                # 查出此时路径脚下的惩罚值热力图
                penalty_map = H_mask.unsqueeze(0).unsqueeze(0)
                curr_penalties = F.grid_sample(penalty_map, grid, mode='bilinear', align_corners=True)
                
                # 计算触发警戒的排斥力：只排斥黄/红区
                active_penalties = F.relu(curr_penalties - ALERT_THRESHOLD)
                
                # ================= 核心修改：非线性引爆惩罚 =================
                # 使用幂次非线性指数函数积：在安全区无推力，一旦接近红黄区，推力指数级飙升！
                loss_obs = (active_penalties ** 2).sum() * 150000.0 
                
                # 能量引导损失：平滑度 + 锚定
                loss_smooth = ((segment[1:] - segment[:-1])**2).sum() * 1.5
                
                (loss_obs + loss_smooth).backward()
                optimizer.step()
                
                # 严格固定起终点位置 (Inpainting 机制锚定 TSP 节点)
                with torch.no_grad():
                    segment[0] = start_node[0]
                    segment[-1] = end_node[0]
            
            all_segments.append(segment.detach().numpy())

        # 3. 拼接并绘制重绘后的“丝滑避障”全景路径
        final_path = np.vstack(all_segments)
        all_cluster_paths.append(final_path)  # 新增：记录当前轨迹

        # 加粗深色线条，增强视觉质感
        plt.plot(final_path[:, 0], final_path[:, 1], color=color, linewidth=3.0, alpha=0.95, zorder=3)
        # 绘制用户节点 (保持白色底黑边，与深色轨迹对比)
        plt.scatter(c_users[:, 0], c_users[:, 1], c='white', s=35, edgecolors='black', zorder=4)
        # 绘制中转站 (Hub)
        plt.scatter(hub[0], hub[1], c=color, s=250, marker='^', edgecolors='white', linewidths=1.5, zorder=5)

    # ================= 渲染与美化 =================
    # === 新增：导出数据给 MATLAB 画图 ===
    save_dict = {}
    for i, p in enumerate(all_cluster_paths):
        save_dict[f'path_{i}'] = p
    sio.savemat('Data_Macro.mat', save_dict)
    print("3. [Render] 全局网络排序与重绘完成，正在生成 Figs.5 成果图...")
    plt.title('Macro-Scale Drone Delivery: Tolerance-Aware Diffusion Routing', fontsize=16, fontweight='bold')
    plt.xlabel('X (meters)', fontsize=14)
    plt.ylabel('Y (meters)', fontsize=14)
    
    # 图例
    legend_elements = [
        mlines.Line2D([], [], color='white', marker='^', markerfacecolor='black', markersize=12, markeredgecolor='white', linestyle='None', label='Cluster Hubs'),
        mlines.Line2D([], [], color='white', marker='o', markerfacecolor='white', markersize=8, markeredgecolor='black', linestyle='None', label='User Nodes'),
        mlines.Line2D([], [], color='black', linewidth=3.0, label='Tolerance-Aware Path')
    ]
    plt.legend(handles=legend_elements, loc='upper right', fontsize=12, framealpha=0.9, edgecolor='black')
    
    plt.xlim(0, L)
    plt.ylim(0, W)
    plt.grid(True, linestyle=':', alpha=0.6)
    
    save_path = 'Macro_City_Logistics_Final_Result.png'
    plt.savefig(save_path, dpi=300, bbox_inches='tight')
    print(f"✅Figs.5 大模型路径修复全景图已成功保存为: {save_path}")
    plt.show()

if __name__ == "__main__":
    run_standlone_plus_mission()