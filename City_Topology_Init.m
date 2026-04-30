% =========================================================================
% IEEE Paper: Full 3D Urban Topology, Heatmap & Trajectory Plotting
% Features: Strict Zero-Overlap, 1 CBD + 2 Industrial + 1 Res, Fixed Seed
% Fix: Corrected imagesc transpose bug for accurate NW/SE visualization
% =========================================================================
clear; clc; close all;
rng(42); % 固定随机种子，保证论文图表的可复现性

%% 1. 场景参数与异构用户生成
L = 5000; W = 5000; 
n_cbd = 100; n_ind1 = 60; n_res = 70; n_ind2 = 40;       
mu = [1250, 1250; 3750, 1250; 1250, 3750; 3750, 3750]; % 四个象限中心 (CBD, 工业1, 住宅, 工业2)
n_users_arr = [n_cbd, n_ind1, n_res, n_ind2]; 
users = [];
for i = 1:4
    users = [users; mvnrnd(mu(i,:), [200000, 0; 0, 200000], n_users_arr(i))];
end
users(users < 0) = 100; 
users(users(:,1) > L, 1) = L - 100;
users(users(:,2) > W, 2) = W - 100;

%% 2. DBSCAN 聚类与严格无重叠建筑物生成
disp('正在执行严格拒绝采样，生成无重叠高密度大楼，请稍候...');
epsilon = 350; minPts = 4;    
[idx, ~] = dbscan(users, epsilon, minPts);
buildings = []; 
cluster_hubs = []; 

figure('Name', 'Final 3D Delivery Mission', 'Color', 'w', 'Position', [50, 50, 1100, 850]);
hold on; grid on; view(-35, 45); axis([0 L 0 W 0 450]);
xlabel('X (m)'); ylabel('Y (m)'); zlabel('Height (m)');

for c = 1:max(idx)
    c_idx = (idx == c);
    c_users = users(c_idx, :);
    T_x = mean(c_users(:,1)); T_y = mean(c_users(:,2));
    
    % 根据坐标划分四大区域属性
    if T_x < 2500 && T_y < 2500
        h_m = [200, 350]; col = [0.8, 0.2, 0.2]; % 左下 - CBD
        target_b = randi([20, 30]);              
    elseif T_x > 2500 && T_y < 2500
        h_m = [80, 150]; col = [0.5, 0.5, 0.5];  % 右下 - Industrial 1
        target_b = randi([20, 30]);              
    elseif T_x < 2500 && T_y > 2500
        h_m = [15, 45]; col = [0.2, 0.5, 0.8];   % 左上 - Residential
        target_b = randi([10, 15]);
    else
        h_m = [80, 150]; col = [0.5, 0.5, 0.5];  % 右上 - Industrial 2
        target_b = randi([20, 30]);              
    end
    
    success_b = 0;
    max_retries = 2000; 
    
    for b = 1:target_b
        is_valid = false;
        retries = 0;
        
        while ~is_valid && retries < max_retries
            retries = retries + 1;
            bw = randi([50, 100]); bl = randi([50, 100]); bh = h_m(1) + rand()*(h_m(2)-h_m(1));
            bx = min(c_users(:,1)) - 100 + rand()*(max(c_users(:,1))-min(c_users(:,1)) + 200);
            by = min(c_users(:,2)) - 100 + rand()*(max(c_users(:,2))-min(c_users(:,2)) + 200);
            
            R_curr = sqrt((bw/2)^2 + (bl/2)^2);
            
            if bx-R_curr < 0 || bx+R_curr > L || by-R_curr < 0 || by+R_curr > W
                continue;
            end
            
            is_valid = true;
            
            if ~isempty(buildings)
                dist_b = sqrt((buildings(:,1)-bx).^2 + (buildings(:,2)-by).^2);
                R_exist = sqrt((buildings(:,3)/2).^2 + (buildings(:,4)/2).^2);
                if any(dist_b < (R_curr + R_exist + 20))
                    is_valid = false; continue;
                end
            end
            
            dist_u = sqrt((users(:,1)-bx).^2 + (users(:,2)-by).^2);
            if any(dist_u < (R_curr + 40))
                is_valid = false; continue;
            end
            
            dist_h = sqrt((T_x-bx)^2 + (T_y-by)^2);
            if dist_h < (R_curr + 80)
                is_valid = false; continue;
            end
        end
        
        if is_valid
            buildings = [buildings; bx, by, bw, bl, bh];
            draw_aabb(bx, by, bw, bl, bh, col);
            success_b = success_b + 1;
        end
    end
    
    T_z = 40;
    plot3(T_x, T_y, T_z, '^', 'MarkerSize', 10, 'MarkerFaceColor', 'y', 'MarkerEdgeColor', 'k');
    plot3([T_x, T_x], [T_y, T_y], [0, T_z], 'k-', 'LineWidth', 1.5);
    
    cluster_hubs = [cluster_hubs; T_x, T_y, T_z];
    scatter3(c_users(:,1), c_users(:,2), zeros(sum(c_idx),1), 20, col, 'filled', 'MarkerEdgeColor', 'k');
end

M_cloud = [L/2, W/2, 400];
plot3(M_cloud(1), M_cloud(2), M_cloud(3), 'p', 'MarkerSize', 20, 'MarkerFaceColor', 'r', 'MarkerEdgeColor', 'k');
plot3([L/2, L/2], [W/2, W/2], [0, 400], 'r-', 'LineWidth', 2);

%% 3. 计算通信惩罚热力图并生成 TSP 序列
disp('正在基于真实的 3D 物理遮挡计算通信惩罚热力图，请稍候...');
target_c = 1; 
target_users = users(idx == target_c, :);
hub_pos = cluster_hubs(target_c, 1:2);
all_pts = [hub_pos; target_users];
order = 1; unvisited = 2:size(all_pts,1); curr = 1;

while ~isempty(unvisited)
    [~, n_i] = min(sum((all_pts(unvisited,:) - all_pts(curr,:)).^2, 2));
    curr = unvisited(n_i); order = [order, curr]; unvisited(n_i) = [];
end
tsp_path_nodes = all_pts([order, 1], :); 

H_V = 125; res = 25;            
x_vec = 0:res:L; y_vec = 0:res:W;
[X_grid, Y_grid] = meshgrid(x_vec, y_vec);
H_joint = zeros(size(X_grid)); 
P_V = 0.1; noise = 1e-11;             

for i = 1:size(X_grid, 1)
    for j = 1:size(X_grid, 2)
        UAV_pos = [X_grid(i,j), Y_grid(i,j), H_V];
        d_M = norm(UAV_pos - M_cloud);
        
        penalty_dB = 0;
        min_x = min(UAV_pos(1), M_cloud(1)); max_x = max(UAV_pos(1), M_cloud(1));
        min_y = min(UAV_pos(2), M_cloud(2)); max_y = max(UAV_pos(2), M_cloud(2));
        
        for b = 1:size(buildings, 1)
            bx = buildings(b,1); by = buildings(b,2);
            bw = buildings(b,3); bl = buildings(b,4); bh = buildings(b,5);
            
            if bh < H_V || bx+bw/2 < min_x || bx-bw/2 > max_x || by+bl/2 < min_y || by-bl/2 > max_y
                continue;
            end
            
            cross1 = (bx-bw/2 - UAV_pos(1))*(M_cloud(2) - UAV_pos(2)) - (by-bl/2 - UAV_pos(2))*(M_cloud(1) - UAV_pos(1));
            cross2 = (bx+bw/2 - UAV_pos(1))*(M_cloud(2) - UAV_pos(2)) - (by+bl/2 - UAV_pos(2))*(M_cloud(1) - UAV_pos(1));
            
            if cross1 * cross2 < 0 
                depth = bh - H_V; 
                penalty_dB = max(penalty_dB, 15 + 0.5 * depth); 
            end
        end
        loss_linear = 10^(-penalty_dB / 10);
        SNR_M = (P_V * loss_linear) / (d_M^2 * noise);
        H_joint(i,j) = max(10*log10(SNR_M), 0); 
    end
end

H_joint = imgaussfilt(H_joint, 3);
H_snr_norm = (H_joint - min(H_joint(:))) / (max(H_joint(:)) - min(H_joint(:)));
H_mask = 1 - H_snr_norm; 

% =========================================================================
% 【修正核心Bug】：去掉了 H_mask 后面的单引号转置！
% =========================================================================
figure('Name', 'H_joint Penalty Condition Mask', 'Color', 'w', 'Position', [1200, 200, 700, 600]);
imagesc(x_vec, y_vec, H_mask); % 这里去掉了转置！
set(gca, 'YDir', 'normal'); 
colormap('jet'); 
c = colorbar;
c.Label.String = 'Penalty Level (1 = Danger/Red, 0 = Safe/Blue)';
c.Label.FontSize = 11; c.Label.FontWeight = 'bold';
title('Spatial Joint Communication Penalty Field (Z = 120m)');
xlabel('X (m)'); ylabel('Y (m)');

save('Urban_Mask_Data.mat', 'L', 'W', 'H_mask', 'users', 'idx', 'cluster_hubs');
disp('✅ 严格无重叠环境生成完毕！Urban_Mask_Data.mat 已导出，请运行 Python 代码。');

%% 辅助函数
function draw_aabb(cx, cy, w, l, h, col)
    x = cx + [-w/2, w/2, w/2, -w/2, -w/2, w/2, w/2, -w/2];
    y = cy + [-l/2, -l/2, l/2, l/2, -l/2, -l/2, l/2, l/2];
    z = [0, 0, 0, 0, h, h, h, h];
    f = [1 2 6 5; 2 3 7 6; 3 4 8 7; 4 1 5 8; 5 6 7 8];
    patch('Vertices', [x' y' z'], 'Faces', f, 'FaceColor', col, 'FaceAlpha', 0.5, 'EdgeColor', [0.3 0.3 0.3]);
end

save('Urban_Mask_Data.mat', 'L', 'W', 'H_mask', 'users', 'idx', 'cluster_hubs', 'buildings');