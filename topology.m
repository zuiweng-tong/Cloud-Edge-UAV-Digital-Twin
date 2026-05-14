% =========================================================================
% IEEE Paper: Full 3D Urban Topology & ITU-R P.526 Diffraction Heatmap
% Fix: Modified to 'Light Jet' colormap for a brighter blue background
% =========================================================================
clear; clc; close all;
%rng(42); % 固定随机种子

%% 1. 场景参数与异构用户生成
L = 5000; W = 5000; 
n_cbd = 100; n_ind1 = 60; n_res = 70; n_ind2 = 40;       
mu = [1250, 1250; 3750, 1250; 1250, 3750; 3750, 3750]; 
n_users_arr = [n_cbd, n_ind1, n_res, n_ind2]; 
users = [];
for i = 1:4
    users = [users; mvnrnd(mu(i,:), [200000, 0; 0, 200000], n_users_arr(i))];
end
users(users < 0) = 100; users(users(:,1) > L, 1) = L - 100; users(users(:,2) > W, 2) = W - 100;

%% 2. DBSCAN 聚类与建筑物生成 (Figure 1: 3D Topology)
disp('正在生成 3D 城市拓扑，请稍候...');
epsilon = 350; minPts = 4;    
[idx, ~] = dbscan(users, epsilon, minPts);
buildings = []; cluster_hubs = []; 

figure('Name', 'Refined 3D Urban Topology', 'Color', 'w', 'Position', [50, 50, 1000, 800]);
hold on; grid on; view(-35, 45); axis([0 L 0 W 0 500]);
xlabel('X (m)'); ylabel('Y (m)'); zlabel('Height (m)');

for c = 1:max(idx)
    c_idx = (idx == c); c_users = users(c_idx, :);
    T_x = mean(c_users(:,1)); T_y = mean(c_users(:,2));
    
    if T_x < 2500 && T_y < 2500, h_m_range = [200, 350]; col = [0.8, 0.2, 0.2]; target_b = randi([20, 30]);
    elseif T_x > 2500 && T_y < 2500, h_m_range = [80, 150]; col = [0.5, 0.5, 0.5]; target_b = randi([20, 30]);
    elseif T_x < 2500 && T_y > 2500, h_m_range = [15, 45]; col = [0.2, 0.5, 0.8]; target_b = randi([10, 15]);
    else, h_m_range = [80, 150]; col = [0.5, 0.5, 0.5]; target_b = randi([20, 30]); end
    
    for b = 1:target_b
        is_valid = false; retries = 0;
        while ~is_valid && retries < 1000
            retries = retries + 1;
            bw = randi([50, 100]); bl = randi([50, 100]); bh = h_m_range(1) + rand()*(h_m_range(2)-h_m_range(1));
            bx = min(c_users(:,1)) - 100 + rand()*(max(c_users(:,1))-min(c_users(:,1)) + 200);
            by = min(c_users(:,2)) - 100 + rand()*(max(c_users(:,2))-min(c_users(:,2)) + 200);
            R_curr = sqrt((bw/2)^2 + (bl/2)^2);
            if bx-R_curr < 0 || bx+R_curr > L || by-R_curr < 0 || by+R_curr > W, continue; end
            is_valid = true;
            if ~isempty(buildings)
                dist_b = sqrt((buildings(:,1)-bx).^2 + (buildings(:,2)-by).^2);
                if any(dist_b < (R_curr + sqrt((buildings(:,3)/2).^2 + (buildings(:,4)/2).^2) + 20)), is_valid = false; continue; end
            end
        end
        if is_valid
            buildings = [buildings; bx, by, bw, bl, bh];
            draw_aabb(bx, by, bw, bl, bh, col);
        end
    end
    T_z = 40;
    plot3(T_x, T_y, T_z, '^', 'MarkerSize', 10, 'MarkerFaceColor', 'y', 'MarkerEdgeColor', 'k');
    plot3([T_x, T_x], [T_y, T_y], [0, T_z], 'k-', 'LineWidth', 1.5);
    cluster_hubs = [cluster_hubs; T_x, T_y, T_z];
    scatter3(c_users(:,1), c_users(:,2), zeros(sum(c_idx),1), 20, col, 'filled', 'MarkerEdgeColor', 'k');
end

% === 寻找最高大楼作为计算中心 ===
[max_bh, max_b_idx] = max(buildings(:, 5)); 
tallest_bx = buildings(max_b_idx, 1);
tallest_by = buildings(max_b_idx, 2);
M_cloud = [tallest_bx, tallest_by, max_bh + 50]; 

plot3(M_cloud(1), M_cloud(2), M_cloud(3), 'p', 'MarkerSize', 20, 'MarkerFaceColor', 'r', 'MarkerEdgeColor', 'k');
plot3([tallest_bx, tallest_bx], [tallest_by, tallest_by], [max_bh, M_cloud(3)], 'r-', 'LineWidth', 2);
title('Heterogeneous 3D Urban Topology & Digital Twin Network');
hold off;

%% 3. 基于 ITU-R P.526 的衍射惩罚热力图 (Figure 2)
disp('正在演算 ITU-R P.526 纯衍射阴影惩罚，这需要大约几十秒，请耐心等待...');
tic; 
freq = 2.4e9; lambda = 3e8 / freq;
H_V_slice = 125; 
res = 25; x_vec = 0:res:L; y_vec = 0:res:W;
[X_grid, Y_grid] = meshgrid(x_vec, y_vec);
Diffraction_Penalty = zeros(size(X_grid)); 

for i = 1:size(X_grid, 1)
    for j = 1:size(X_grid, 2)
        UAV_pos = [X_grid(i,j), Y_grid(i,j), H_V_slice];
        max_L_vm = 0; 
        
        for b = 1:size(buildings, 1)
            bx = buildings(b,1); by = buildings(b,2); 
            bw = buildings(b,3); bl = buildings(b,4); bh = buildings(b,5);
            
            if bx == M_cloud(1) && by == M_cloud(2), continue; end 
            if bh < H_V_slice, continue; end
            
            vec_UC = M_cloud(1:2) - UAV_pos(1:2);
            vec_UB = [bx, by] - UAV_pos(1:2);
            norm_UC2 = norm(vec_UC)^2;
            if norm_UC2 == 0, continue; end
            proj = dot(vec_UB, vec_UC) / norm_UC2;
            
            if proj < 0 || proj > 1, continue; end
            
            min_x = min(UAV_pos(1), M_cloud(1)); max_x = max(UAV_pos(1), M_cloud(1));
            min_y = min(UAV_pos(2), M_cloud(2)); max_y = max(UAV_pos(2), M_cloud(2));
            if bx+bw/2 < min_x || bx-bw/2 > max_x || by+bl/2 < min_y || by-bl/2 > max_y
                continue;
            end
            
            cross1 = (bx-bw/2 - UAV_pos(1))*(M_cloud(2) - UAV_pos(2)) - (by-bl/2 - UAV_pos(2))*(M_cloud(1) - UAV_pos(1));
            cross2 = (bx+bw/2 - UAV_pos(1))*(M_cloud(2) - UAV_pos(2)) - (by+bl/2 - UAV_pos(2))*(M_cloud(1) - UAV_pos(1));
            
            if cross1 * cross2 <= 0 
                h_los = UAV_pos(3) + proj * (M_cloud(3) - UAV_pos(3));
                hm = bh - h_los; 
                
                if hm > 0
                    d1 = proj * norm(vec_UC);
                    d2 = (1 - proj) * norm(vec_UC);
                    vm = hm * sqrt(2 * (d1 + d2) / (lambda * d1 * d2));
                    if vm > -0.78
                        L_vm = 6.9 + 20 * log10(sqrt((vm - 0.1)^2 + 1) + vm - 0.1);
                        max_L_vm = max(max_L_vm, L_vm);
                    end
                end
            end
        end
        Diffraction_Penalty(i,j) = max_L_vm; 
    end
end

H_mask = imgaussfilt(Diffraction_Penalty, 2);
if max(H_mask(:)) > 0
    H_mask = H_mask / max(H_mask(:));
end

% ================= 定制 "浅蓝底" Jet 色带 =================
% 保持红黄高对比度，但把极暗的深蓝替换为清爽的浅海蓝
c_nodes = [
    0.25, 0.50, 0.95;  % 浅海蓝 (Light Ocean Blue) - 替换深黑蓝
    0.00, 0.65, 1.00;  % 亮蓝
    0.00, 1.00, 1.00;  % 青色
    1.00, 1.00, 0.00;  % 黄色
    1.00, 0.00, 0.00;  % 红色
    0.50, 0.00, 0.00   % 暗红
];
node_pos = [1, 38, 90, 166, 217, 256];
light_jet = zeros(256, 3);
for i = 1:3
    light_jet(:,i) = interp1(node_pos, c_nodes(:,i), 1:256, 'linear');
end

figure('Name', 'Spatial Diffraction Penalty Field', 'Color', 'w', 'Position', [1100, 200, 700, 600]);
imagesc(x_vec, y_vec, H_mask); 
set(gca, 'YDir', 'normal'); 
colormap(light_jet); % 应用浅蓝底定制色带

xlabel('X (m)'); ylabel('Y (m)');
title('Spatial Diffraction Penalty Field (Z = 125m Slice)');

c = colorbar; 
c.Label.String = 'Normalized NLoS Diffraction Penalty (1 = High Risk, 0 = Safe)';

% ================= 强制导出到当前代码路径 =================
current_dir = fileparts(mfilename('fullpath'));
if isempty(current_dir)
    current_dir = pwd; 
end
mat_file_path = fullfile(current_dir, 'Urban_Mask_Data.mat');
save(mat_file_path, 'L', 'W', 'H_mask', 'users', 'idx', 'cluster_hubs', 'buildings');

toc; 
disp(' ');
fprintf('✅ 数据已强制导出到该绝对路径下：\n👉 %s\n', mat_file_path);

%% 辅助函数
function draw_aabb(cx, cy, w, l, h, col)
    x = cx + [-w/2, w/2, w/2, -w/2, -w/2, w/2, w/2, -w/2];
    y = cy + [-l/2, -l/2, l/2, l/2, -l/2, -l/2, l/2, l/2];
    z = [0, 0, 0, 0, h, h, h, h]; f = [1 2 6 5; 2 3 7 6; 3 4 8 7; 4 1 5 8; 5 6 7 8];
    patch('Vertices', [x' y' z'], 'Faces', f, 'FaceColor', col, 'FaceAlpha', 0.5, 'EdgeColor', [0.3 0.3 0.3]);
end