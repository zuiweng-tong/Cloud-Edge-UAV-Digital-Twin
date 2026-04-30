import scipy.io as sio
import numpy as np
import torch
import torch.nn.functional as F
import matplotlib.pyplot as plt
import matplotlib.lines as mlines
import copy

# =========================================================================
# IEEE Paper: Multi-Cluster Loop via Exponential-Aware Diffusion Inpainting
# Features: 1. Full city multi-cluster routing (Standalone Python Visualization)
#           2. Disentanglement TSP sorting for macro topology
#           3. Strict inpainting + EXPONENTIAL penalty guidance for exaggerated evasion
#           [新增] 4. Node-Driven Altitude Control (节点风险驱动的三维高度分配)
# =========================================================================

def tsp_nearest_neighbor_with_2opt(nodes):
    num_pts = len(nodes)
    order = [0]
    unvisited = list(range(1, num_pts))
    curr = 0
    while unvisited:
        dists = np.sum((nodes[unvisited] - nodes[curr])**2, axis=1)
        next_idx = int(np.argmin(dists))
        curr = unvisited[next_idx]
        order.append(curr)
        unvisited.pop(next_idx)
    
    order_np = np.array(order)
    nodes_np = nodes[order_np]
    for i in range(1, num_pts - 2):
        for j in range(i + 1, num_pts):
            if j - i == 1: continue
            new_path = copy.deepcopy(nodes_np)
            new_path[i:j+1] = new_path[i:j+1][::-1]
            old_dist = np.sum(np.sqrt(np.sum((nodes_np[1:] - nodes_np[:-1])**2, axis=1)))
            new_dist = np.sum(np.sqrt(np.sum((new_path[1:] - new_path[:-1])**2, axis=1)))
            if new_dist < old_dist:
                nodes_np = new_path
                order_np[i:j+1] = order_np[i:j+1][::-1]
    
    final_order = order_np.tolist()
    final_order.append(order[0])
    return final_order

def run_standlone_plus_mission():
    print("1. [Loading] 正在加载城市环境与 TSP 目标序列...")
    try:
        mat_data = sio.loadmat('Urban_Mask_Data.mat')
    except FileNotFoundError:
        print("Error: 未找到 'Urban_Mask_Data.mat'。请确保已运行 MATLAB 并导出数据。")
        return

    H_mask = torch.tensor(mat_data['H_mask'], dtype=torch.float32)
    L = float(mat_data['L'].item())
    W = float(mat_data['W'].item())
    users = mat_data['users']
    idx = mat_data['idx'].flatten()
    cluster_hubs = mat_data['cluster_hubs']
    
    ALERT_THRESHOLD = 0.5 
    H_CRUISE = 350.0  # 默认巡航高度
    H_CLIMB = 400.0   # 风险区拉升高度
    
    # 辅助函数：获取特定坐标点的风险惩罚值
    def get_node_penalty(x, y):
        norm_x = (x / L) * 2.0 - 1.0
        norm_y = (y / W) * 2.0 - 1.0
        grid = torch.tensor([[[[norm_x, norm_y]]]], dtype=torch.float32)
        pen = F.grid_sample(H_mask.unsqueeze(0).unsqueeze(0), grid, align_corners=True)
        return pen.item()
    
    unique_clusters = np.unique(idx)
    unique_clusters = unique_clusters[unique_clusters > 0] 
    
    print(f"2. [Processing] 正在演算 {len(unique_clusters)} 个业务簇，评估节点风险并重绘路径...")
    all_cluster_paths = []

    # 保留原版画布设定
    plt.figure(figsize=(14, 12), facecolor='white')
    plt.imshow(H_mask.numpy(), origin='lower', extent=[0, L, 0, W], cmap='jet', alpha=0.85)
    cluster_colors = ['black', 'darkred', 'purple', 'darkslategrey', 'saddlebrown']

    for c_idx in unique_clusters:
        c_id = int(c_idx)
        c_users = users[idx == c_id]
        hub = cluster_hubs[c_id - 1, :2] 
        color = cluster_colors[(c_id - 1) % len(cluster_colors)]
        
        all_pts_arr = np.vstack([hub, c_users])
        sorted_order = tsp_nearest_neighbor_with_2opt(all_pts_arr)
        tsp_nodes = torch.tensor(all_pts_arr[sorted_order], dtype=torch.float32)
        
        # 评估每个节点的风险，决定其对应的高度
        node_alts = []
        for i in range(len(tsp_nodes)):
            if get_node_penalty(tsp_nodes[i, 0].item(), tsp_nodes[i, 1].item()) > ALERT_THRESHOLD:
                node_alts.append(H_CLIMB)  # 节点处于高风险区，抬升
            else:
                node_alts.append(H_CRUISE) # 安全区，保持巡航高度
                
        all_segments = []
        print(f"   -> 正在规划 Cluster {c_id} (包含 {len(c_users)} 个用户)...")

        for i in range(len(tsp_nodes) - 1):
            start_node = tsp_nodes[i:i+1]
            end_node = tsp_nodes[i+1:i+2]
            start_alt = node_alts[i]
            end_alt = node_alts[i+1]
            
            # 原版二维直线初始化与扩散优化
            t = torch.linspace(0, 1, 30).unsqueeze(1)
            segment_xy = (start_node + t * (end_node - start_node)).requires_grad_(True)
            optimizer = torch.optim.Adam([segment_xy], lr=15.0)
            
            for _ in range(100):
                optimizer.zero_grad()
                norm_x = (segment_xy[:, 0] / L) * 2.0 - 1.0
                norm_y = (segment_xy[:, 1] / W) * 2.0 - 1.0
                grid = torch.stack([norm_x, norm_y], dim=-1).view(1, 1, -1, 2)
                
                curr_penalties = F.grid_sample(H_mask.unsqueeze(0).unsqueeze(0), grid, mode='bilinear', align_corners=True)
                active_penalties = F.relu(curr_penalties - ALERT_THRESHOLD)
                
                loss_obs = (active_penalties ** 2).sum() * 150000.0 
                loss_smooth = ((segment_xy[1:] - segment_xy[:-1])**2).sum() * 1.5
                
                (loss_obs + loss_smooth).backward()
                optimizer.step()
                
                with torch.no_grad():
                    segment_xy[0] = start_node[0]
                    segment_xy[-1] = end_node[0]
            
            # 优化完毕，为当前的二维轨迹附加 Z 轴高度 (线性平滑过渡)
            z_segment = start_alt + t * (end_alt - start_alt)
            segment_3d = torch.cat([segment_xy.detach(), z_segment], dim=1)
            all_segments.append(segment_3d.numpy())

        final_path = np.vstack(all_segments)
        all_cluster_paths.append(final_path)

        # 原版的 2D 绘图逻辑，用于对照
        plt.plot(final_path[:, 0], final_path[:, 1], color=color, linewidth=3.0, alpha=0.95, zorder=3)
        plt.scatter(c_users[:, 0], c_users[:, 1], c='white', s=35, edgecolors='black', zorder=4)
        plt.scatter(hub[0], hub[1], c=color, s=250, marker='^', edgecolors='white', linewidths=1.5, zorder=5)

    # 导出包含 Z 轴数据的供 MATLAB 使用
    save_dict = {}
    for i, p in enumerate(all_cluster_paths):
        save_dict[f'path_{i}'] = p
    sio.savemat('Data_Macro_3D.mat', save_dict)
    
    print("3. [Render] 全局网络排序与重绘完成，正在生成二维成果图...")
    plt.title('Macro-Scale Drone Delivery: Tolerance-Aware Diffusion Routing', fontsize=16, fontweight='bold')
    plt.xlabel('X (meters)', fontsize=14)
    plt.ylabel('Y (meters)', fontsize=14)
    
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
    print(f"✅ Figs.5 2D 全景图已保存为: {save_path}")
    print(f"✅ 3D 数据已保存为 Data_Macro_3D.mat, 请运行 MATLAB 绘制 3D 轨迹图。")
    plt.show()

if __name__ == "__main__":
    run_standlone_plus_mission()