import scipy.io as sio
import numpy as np
import torch
import torch.nn.functional as F
import copy
from scipy.ndimage import gaussian_filter1d

# =========================================================================
# IEEE Paper: Multi-Cluster Loop via Exponential-Aware Diffusion Inpainting
# 功能: 纯计算引擎。不涉及任何 matplotlib 绘图。
# 负责 TSP 排序、条件扩散模型优化、高斯动力学平滑及节点误差补偿。
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

def smooth_aerodynamic_trajectory(path, sigma=7.0, segment_len=30):
    """【核心机制】：高斯滤波生成流线，并通过误差补偿强制轨迹严格穿过所有用户节点"""
    smoothed_path = np.zeros_like(path)
    for i in range(path.shape[1]):
        smoothed_path[:, i] = gaussian_filter1d(path[:, i], sigma=sigma, mode='nearest')
    
    corrected_path = np.copy(smoothed_path)
    num_segments = len(path) // segment_len
    
    for s in range(num_segments):
        idx_start = s * segment_len
        idx_end = idx_start + segment_len - 1
        
        err_start = path[idx_start] - smoothed_path[idx_start]
        err_end = path[idx_end] - smoothed_path[idx_end]
        
        t = np.linspace(0, 1, segment_len).reshape(-1, 1)
        correction = (1 - t) * err_start + t * err_end
        
        corrected_path[idx_start:idx_end+1] += correction
        
    return corrected_path

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
    H_CRUISE = 350.0 
    H_CLIMB = 400.0   
    
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

    for c_idx in unique_clusters:
        c_id = int(c_idx)
        c_users = users[idx == c_id]
        hub = cluster_hubs[c_id - 1, :2] 
        
        all_pts_arr = np.vstack([hub, c_users])
        sorted_order = tsp_nearest_neighbor_with_2opt(all_pts_arr)
        tsp_nodes = torch.tensor(all_pts_arr[sorted_order], dtype=torch.float32)
        
        node_alts = []
        for i in range(len(tsp_nodes)):
            if get_node_penalty(tsp_nodes[i, 0].item(), tsp_nodes[i, 1].item()) > ALERT_THRESHOLD:
                node_alts.append(H_CLIMB)  
            else:
                node_alts.append(H_CRUISE) 
                
        all_segments = []
        print(f"   -> 正在规划 Cluster {c_id} (包含 {len(c_users)} 个用户)...")

        for i in range(len(tsp_nodes) - 1):
            start_node = tsp_nodes[i:i+1]
            end_node = tsp_nodes[i+1:i+2]
            start_alt = node_alts[i]
            end_alt = node_alts[i+1]
            
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
            
            z_segment = start_alt + t * (end_alt - start_alt)
            segment_3d = torch.cat([segment_xy.detach(), z_segment], dim=1)
            all_segments.append(segment_3d.numpy())

        raw_final_path = np.vstack(all_segments)
        
        # 应用高斯平滑及误差补偿
        smooth_final_path = smooth_aerodynamic_trajectory(raw_final_path, sigma=7.0, segment_len=30)
        all_cluster_paths.append(smooth_final_path)

    print("3. [Saving] 计算完毕，正在保存轨迹数据至 Data_Macro_3D.mat...")
    save_dict = {}
    for i, p in enumerate(all_cluster_paths):
        save_dict[f'path_{i}'] = p
    sio.savemat('Data_Macro_3D.mat', save_dict)
    print("✅ 成功！请前往 MATLAB 运行绘图脚本生成 2D/3D 高清论文图片。")

if __name__ == "__main__":
    run_standlone_plus_mission()