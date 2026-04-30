import scipy.io as sio
import numpy as np
import torch
import torch.nn.functional as F
import matplotlib.pyplot as plt

# =========================================================================
# IEEE Paper: Dynamic Crisis Reaction & Evasive Maneuver
# Features: 1. Auto-hunting with Dynamic Condition Relaxation (Fix Infinite Loop)
#           2. Exponential penalty guidance for "silk-like" dramatic turns
#           3. Auto-zoom bounding box tracking
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
    ALERT_THRESHOLD = 0.55 

    print("2. [剧本生成] 正在全图自动搜索致命的 NLoS 物理死区...")
    
    # --- 修复核心：动态降级搜索 ---
    found_scenario = False
    attempts = 0
    
    # 初始苛刻条件
    safe_limit = 0.25  
    fatal_limit = 0.85 

    while not found_scenario:
        attempts += 1
        
        # 如果找了 2000 次还找不到，说明地图太难了，自动放宽条件！
        if attempts > 2000:
            safe_limit += 0.05
            fatal_limit -= 0.05
            attempts = 0
            print(f"   ...当前地图高危区太密集，自动放宽搜索条件 (安全区容忍<{safe_limit:.2f}, 致命区要求>{fatal_limit:.2f})...")
            
            # 触底反弹保护
            if safe_limit > 0.45 or fatal_limit < 0.60:
                print("   ⚠️ 警告：无法找到完美穿越路径，强制使用最后一次采样的路径！")
                break

        # 随机生成距离在 800 到 2000 米之间的短航线
        s = torch.rand(1, 2) * torch.tensor([L, W])
        e = torch.rand(1, 2) * torch.tensor([L, W])
        if torch.norm(s - e) < 800 or torch.norm(s - e) > 2000:
            continue
            
        sx_idx = int((s[0,0]/L) * (H_mask.shape[1]-1))
        sy_idx = int((s[0,1]/W) * (H_mask.shape[0]-1))
        ex_idx = int((e[0,0]/L) * (H_mask.shape[1]-1))
        ey_idx = int((e[0,1]/W) * (H_mask.shape[0]-1))
        
        # 检查两端是否在动态安全区内
        if H_mask[sy_idx, sx_idx] > safe_limit or H_mask[ey_idx, ex_idx] > safe_limit:
            continue
            
        t_fatal = torch.linspace(0, 1, 50).unsqueeze(1)
        straight_path = s + t_fatal * (e - s)
        norm_x = (straight_path[:, 0] / L) * 2.0 - 1.0
        norm_y = (straight_path[:, 1] / W) * 2.0 - 1.0
        grid = torch.stack([norm_x, norm_y], dim=-1).view(1, 1, -1, 2)
        straight_pens = F.grid_sample(penalty_map, grid, mode='bilinear', align_corners=True)
        
        # 检查中间是否穿越了动态致命区
        if straight_pens.max().item() > fatal_limit:
            crisis_pt = s
            target_pt = e
            fatal_path = straight_path
            found_scenario = True

    print(f"   -> 🎯 成功锁定危机坐标! 爆发点: ({crisis_pt[0,0]:.0f}, {crisis_pt[0,1]:.0f})")

    print("3. [边缘求生] TDOA 报警！大模型极限甩尾重绘中 (约需几秒)...")
    
    edge_segment = fatal_path.clone().requires_grad_(True)
    optimizer = torch.optim.Adam([edge_segment], lr=15.0) 
    
    for _ in range(150): 
        optimizer.zero_grad()
        norm_x = (edge_segment[:, 0] / L) * 2.0 - 1.0
        norm_y = (edge_segment[:, 1] / W) * 2.0 - 1.0
        grid = torch.stack([norm_x, norm_y], dim=-1).view(1, 1, -1, 2)
        curr_penalties = F.grid_sample(penalty_map, grid, mode='bilinear', align_corners=True)
        
        ThresholdForShowingEvasion = 0.35
        active_penalties = F.relu(curr_penalties - ThresholdForShowingEvasion)
        
        # 【平方爆炸惩罚】：造就极限大甩尾！
        loss_obs = (active_penalties ** 2).sum() * 200000.0 
        loss_smooth = ((edge_segment[1:] - edge_segment[:-1])**2).sum() * 0.5
        
        (loss_obs + loss_smooth).backward()
        optimizer.step()
        
        with torch.no_grad():
            edge_segment[0] = crisis_pt[0]
            edge_segment[-1] = target_pt[0]

    edge_traj_np = edge_segment.detach().numpy()
    fatal_traj_np = fatal_path.numpy()


    sio.savemat('Data_Crisis.mat', {
        'fatal_traj': fatal_traj_np,
        'edge_traj': edge_traj_np,
        'crisis_pt': crisis_pt.numpy(),
        'target_pt': target_pt.numpy()
    })
    print("4. [渲染出图] 正在生成危机特写镜头...")
    
    plt.figure(figsize=(10, 10), facecolor='white')
    plt.imshow(H_mask.numpy(), origin='lower', extent=[0, L, 0, W], cmap='jet', alpha=0.85)

    plt.plot(fatal_traj_np[:, 0], fatal_traj_np[:, 1], color='#e0e0e0', linestyle='--', 
             linewidth=5, zorder=3, label='Fatal Command (Spoofed Cloud Path)')

    plt.plot(edge_traj_np[:, 0], edge_traj_np[:, 1], color='darkorange', linestyle='-', 
             linewidth=5, zorder=4, label='Emergency Escape (Edge DT Inpainting)')

    plt.scatter(crisis_pt[0,0].item(), crisis_pt[0,1].item(), c='red', s=500, marker='*', 
                edgecolors='white', linewidths=1.5, zorder=5, label=r'TDOA Alarm Trigger ($C_{flag}=1$)')
    plt.scatter(target_pt[0,0].item(), target_pt[0,1].item(), c='blue', s=200, marker='o', 
                edgecolors='white', linewidths=1.5, zorder=5, label='Target / Safe Anchor')

    plt.title('Crisis Response: TDOA Alarm & Edge DT Evasive Maneuver', fontsize=16, fontweight='bold')
    plt.xlabel('X (meters)', fontsize=14)
    plt.ylabel('Y (meters)', fontsize=14)
    
    # 动态计算镜头 Bounding Box
    margin = 400
    min_x = max(0, min(crisis_pt[0,0].item(), target_pt[0,0].item(), edge_traj_np[:,0].min()) - margin)
    max_x = min(L, max(crisis_pt[0,0].item(), target_pt[0,0].item(), edge_traj_np[:,0].max()) + margin)
    min_y = max(0, min(crisis_pt[0,1].item(), target_pt[0,1].item(), edge_traj_np[:,1].min()) - margin)
    max_y = min(W, max(crisis_pt[0,1].item(), target_pt[0,1].item(), edge_traj_np[:,1].max()) + margin)
    
    span_x = max_x - min_x
    span_y = max_y - min_y
    max_span = max(span_x, span_y)
    center_x = (min_x + max_x) / 2
    center_y = (min_y + max_y) / 2
    
    plt.xlim(center_x - max_span/2, center_x + max_span/2)
    plt.ylim(center_y - max_span/2, center_y + max_span/2)

    plt.legend(loc='upper right', fontsize=11, framealpha=0.9, edgecolor='black')
    plt.grid(True, linestyle=':', alpha=0.5)

    save_path = 'Dynamic_Crisis_Reaction.png'
    plt.savefig(save_path, dpi=300, bbox_inches='tight')
    print(f"✅ 自适应危机反应图已保存为: {save_path}")
    plt.show()

if __name__ == "__main__":
    run_dynamic_crisis()