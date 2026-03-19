%% SDR MP3 Player (DSB-SC 零中頻直驅版 - 極簡純低通濾波接收)
% 功能：設定 433MHz LO -> 擷取基頻 IQ -> 純低通濾波 -> 直接提取實部播放
clc; clear; close all;

%% 1. 參數設定
SR = 960e3;             % SDR 硬體取樣率 1.92 MHz
Target_Freq_MHz = 433;  % 接收中心頻率 (必須與 TX 完全相同)
Capture_Time = 15;      % 錄製 15 秒
fs_audio_out = 48e3;    % 最終播放的音訊取樣率 (48 kHz)
fs_proc = 192e3;        % DSP 處理頻率


%% 2. 啟動 SDR 接收硬體
fprintf('=== SDR MP3 極簡接收端 ===\n');
fprintf('正在擷取 %d 秒的空中訊號...\n', Capture_Time);

LO_CHANGE(0, Target_Freq_MHz, Target_Freq_MHz);
set_RX_Ref_Level_ELSDR([0 -10]);

% 擷取第 1 個 Row 的資料 (1 x N 橫向量)
rx_iq = RX(1, SR * Capture_Time);
fprintf('擷取完成！\n');

%% 3. 資料轉置與降取樣
% 轉置為 N x 1 的 Column Vector 以利濾波器處理
if size(rx_iq, 1) == 1
    rx_iq = rx_iq.';
end

% 降取樣
decimation_factor = floor(SR / fs_proc);
rx_baseband = downsample(rx_iq, decimation_factor);

%% 4. 動態相位追蹤法 (Dynamic Squaring Loop)
fprintf('啟動動態相位與頻率追蹤...\n');

% 1. 將基頻訊號平方，消除正負號影響，讓載波相位變成兩倍 (2*theta)
rx_squared = rx_baseband .^ 2;

% 2. 【關鍵改進】設計一個極低頻的追蹤濾波器 (例如 10 Hz)
% 我們不用 mean()，而是用濾波器濾除高頻的音樂變化，只留下隨時間緩慢漂移的頻率差！
[b_track, a_track] = butter(2, 10 / (fs_proc/2));
rx_squared_filtered = filtfilt(b_track, a_track, rx_squared);

% 3. 計算每個時間點的動態相位 (因為平方過，所以要除以 2)
% 注意：現在的 theta_t 是一個長度與音樂相同的陣列，它會跟著時間不斷變化！
theta_t = angle(rx_squared_filtered) / 2;

% 4. 將原始訊號乘上「隨時間變化的反向角度」，完美解開連續漂移
rx_sync = rx_baseband .* exp(-1j * theta_t);

% 5. 進行 15kHz 音樂低通濾波
cutoff_freq = 15e3;
[b_audio, a_audio] = butter(5, cutoff_freq / (fs_proc/2));
rx_filtered = filtfilt(b_audio, a_audio, rx_sync);

% 6. 取實部當作音樂
audio_demod = real(rx_filtered);

%% --- 繪圖證明：DC 導頻相位追蹤效果視覺化 ---
% 開啟一個寬度較大的視窗來並排顯示兩張圖
figure('Name', '導頻相位同步 (Pilot-aided) 效果比較', 'Color', 'w', 'Position', [100, 100, 1000, 400]);

% ==========================================
% 1. 左圖：IQ 星系圖 (Constellation Diagram)
% ==========================================
subplot(1, 2, 1);
plot_step = 10; % 降取樣畫圖避免點數過多卡頓

% 【同步前】包含 DC 與音樂。因為兩台 SDR 有微小頻率差，整體會在 IQ 平面上繞圈圈
scatter(real(rx_baseband(1:plot_step:end)), imag(rx_baseband(1:plot_step:end)), 5, 'r', 'filled', 'MarkerFaceAlpha', 0.2);
hold on;

% 【同步後】將訊號反向旋轉對齊。DC 會被死死釘在 I 軸正半邊 (右側)，音樂則沿著 I 軸左右震盪
scatter(real(rx_sync(1:plot_step:end)), imag(rx_sync(1:plot_step:end)), 5, 'b', 'filled', 'MarkerFaceAlpha', 0.2);

title('IQ 散佈圖 (Constellation)');
xlabel('I 通道 (實部)'); ylabel('Q 通道 (虛部)');
legend('同步前 (相位隨頻率差旋轉)', '同步後 (精準鎖定於 I 軸)', 'Location', 'best');
grid on; axis square;

% 設定對稱的座標軸範圍，讓圓圈看起來更明顯
max_val = max(abs(rx_baseband));
xlim([-max_val max_val]); ylim([-max_val max_val]);


% ==========================================
% 2. 右圖：時域波形 (Time Domain) 衰減比較
% ==========================================
subplot(1, 2, 2);
samples_to_plot = round(0.1 * fs_proc); % 只取前 0.1 秒來觀察波形細節
t_plot = (0:samples_to_plot-1) / fs_proc;

% 【同步前】如果直接取實部，會看到訊號因為相位偏移而產生低頻的忽大忽小 (Fading 包絡線)
plot(t_plot, real(rx_baseband(1:samples_to_plot)), 'r', 'LineWidth', 1);
hold on;

% 【同步後】相位永遠對齊，波形維持穩定且最大的振幅
plot(t_plot, real(rx_sync(1:samples_to_plot)), 'b', 'LineWidth', 1);

title('接收端時域波形比較 (前 0.1 秒)');
xlabel('時間 (秒)'); ylabel('振幅');
legend('同步前 (直接取實部會有嚴重衰減)', '同步後 (振幅穩定還原)', 'Location', 'best');
grid on;

%% 5. 播放與繪圖
% 重採樣回標準音訊格式 (48 kHz)
audio_out = resample(audio_demod, fs_audio_out, fs_proc);

% 正規化音量防止喇叭破音
audio_out = audio_out / max(abs(audio_out));

fprintf('播放極簡解調的音樂！\n');
soundsc(audio_out, fs_audio_out);

% 畫圖觀察
figure('Name', '極簡接收端波形分析', 'Color', 'w');
t_plot = (0:length(audio_out)-1) / fs_audio_out;
plot(t_plot, audio_out, 'k');
title('解調音訊波形');
xlabel('時間 (秒)'); ylabel('振幅'); grid on;