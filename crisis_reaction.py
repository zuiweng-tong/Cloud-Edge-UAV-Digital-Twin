import scipy.io as sio
import numpy as np
import torch
import torch.nn.functional as F

# =========================================================================
# Python 只负责核心计算与梯度优化，将轨迹结果导出给 MATLAB 渲染
# =========================================================================

def run_dynamic_crisis():
    print("1. [环境感知] 加载最新随机生成的城市热力图...")
    try:
        mat_data = sio.loadmat('Urban_Mask_Data.mat')
    except FileNotFoundError:
        print("Error: 未找到 'Urban_Mask_Data.mat'。请先运行 MATLAB 脚本。")
        return

    H_mask = torch.tensor(mat_data['H_mask'], dtype=torch.float32)
    L = float(mat_data['L'].item())
    W = float(mat_data['W'].item())
    penalty_map = H_mask.unsqueeze(0).unsqueeze(0)

    print("2. [剧本生成] 正在全图自动搜索致命的 NLoS 物理死区...")
    found_scenario = False
    attempts = 0
    safe_limit = 0.25  
    fatal_limit = 0.85 

    while not found_scenario:
        attempts += 1
        if attempts > 2000:
            safe_limit += 0.05
            fatal_limit -= 0.05
            attempts = 0
            print(f"   ...自动放宽搜索条件 (安全容忍<{safe_limit:.2f}, 致命要求>{fatal_limit:.2f})...")
            if safe_limit > 0.45 or fatal_limit < 0.60:
                print("   ⚠️ 警告：无法找到完美穿越路径，强制使用最后一次采样！")
                break

        s = torch.rand(1, 2) * torch.tensor([L, W])
        e = torch.rand(1, 2) * torch.tensor([L, W])
        if torch.norm(s - e) < 800 or torch.norm(s - e) > 2000:
            continue
            
        sx_idx = int((s[0,0]/L) * (H_mask.shape[1]-1))
        sy_idx = int((s[0,1]/W) * (H_mask.shape[0]-1))
        ex_idx = int((e[0,0]/L) * (H_mask.shape[1]-1))
        ey_idx = int((e[0,1]/W) * (H_mask.shape[0]-1))
        
        if H_mask[sy_idx, sx_idx] > safe_limit or H_mask[ey_idx, ex_idx] > safe_limit:
            continue
            
        t_fatal = torch.linspace(0, 1, 50).unsqueeze(1)
        straight_path = s + t_fatal * (e - s)
        norm_x = (straight_path[:, 0] / L) * 2.0 - 1.0
        norm_y = (straight_path[:, 1] / W) * 2.0 - 1.0
        grid = torch.stack([norm_x, norm_y], dim=-1).view(1, 1, -1, 2)
        straight_pens = F.grid_sample(penalty_map, grid, mode='bilinear', align_corners=True)
        
        if straight_pens.max().item() > fatal_limit:
            crisis_pt = s
            target_pt = e
            fatal_path = straight_path
            found_scenario = True

    print(f"   -> 🎯 成功锁定危机坐标! 爆发点: ({crisis_pt[0,0]:.0f}, {crisis_pt[0,1]:.0f})")
    print("3. [边缘求生] 大模型极限甩尾重绘中...")
    
    edge_segment = fatal_path.clone().requires_grad_(True)
    optimizer = torch.optim.Adam([edge_segment], lr=15.0) 
    
    for _ in range(150): 
        optimizer.zero_grad()
        norm_x = (edge_segment[:, 0] / L) * 2.0 - 1.0
        norm_y = (edge_segment[:, 1] / W) * 2.0 - 1.0
        grid = torch.stack([norm_x, norm_y], dim=-1).view(1, 1, -1, 2)
        curr_penalties = F.grid_sample(penalty_map, grid, mode='bilinear', align_corners=True)
        
        active_penalties = F.relu(curr_penalties - 0.35)
        loss_obs = (active_penalties ** 2).sum() * 200000.0 
        loss_smooth = ((edge_segment[1:] - edge_segment[:-1])**2).sum() * 0.5
        
        (loss_obs + loss_smooth).backward()
        optimizer.step()
        
        with torch.no_grad():
            edge_segment[0] = crisis_pt[0]
            edge_segment[-1] = target_pt[0]

    # 将所有必要数据保存，供 MATLAB 使用
    sio.savemat('Data_Crisis_Result.mat', {
        'fatal_traj': fatal_path.numpy(),
        'edge_traj': edge_segment.detach().numpy(),
        'crisis_pt': crisis_pt.numpy(),
        'target_pt': target_pt.numpy()
    })
    
    print("4. ✅ 计算完成！数据已保存至 'Data_Crisis_Result.mat'。请运行 MATLAB 脚本进行高级渲染。")

if __name__ == "__main__":
    run_dynamic_crisis()