%--- 1. 讀取音訊檔案 ---
fprintf('=== MP3 DSB-SC 音樂電台 (雙聲道立體聲) ===\n');
mp3_filename = 'music.mp3';

% 檢查檔案是否存在
if ~isfile(mp3_filename)
    error('錯誤：找不到檔案 %s', mp3_filename);
end

% 讀取音訊檔案
[y, fs_audio] = audioread(mp3_filename);

% 若原始檔案為單聲道，複製成雙聲道以統一後續處理格式
if size(y, 2) == 1
    y = [y, y];
end

% 根據 Loop_Duration 計算取樣點數並裁切
Loop_Duration = 20;
samples_Duration = floor(Loop_Duration * fs_audio);
y = y(1:min(end, samples_Duration), :);

fprintf('成功讀取音訊，裁切長度：%.2f 秒\n', length(y)/fs_audio);

% --- 2. 參數與重採樣 ---
fs = 1e6;                 % 通訊採樣率: 1 MHz
fc = 0.1e6;               % 載波頻率: 0.1 MHz

fprintf('正在進行重採樣至 1MHz... (請稍候)\n');
% 將音訊提升到通訊採樣率 (mt 現在會是 N x 2 的矩陣)
mt = resample(y, fs, fs_audio); 
L = size(mt, 1);
t = (0:L-1)' / fs;        % 轉為直行向量 (N x 1)

% --- 3. FDM 調變 (分頻多工) ---
fc1 = 100e3;              % 左聲道載波頻率: 100 kHz
fc2 = 150e3;              % 右聲道載波頻率: 150 kHz

c1 = cos(2*pi*fc1*t);     % 左聲道載波
c2 = cos(2*pi*fc2*t);     % 右聲道載波

% 左聲道乘上 c1，右聲道乘上 c2，並相加成單一傳輸訊號
st_fdm = mt(:, 1) .* c1 + mt(:, 2) .* c2; 

% --- 4. FDM 解調與 FIR 濾波 ---
% 接收端分別用對應的載波進行相干解調
demod_raw_L = st_fdm .* c1;
demod_raw_R = st_fdm .* c2;

% FIR 濾波器設計 (截止頻率 15kHz)
N_filt = 101;
fc_lpf = 15e3;            
wc = 2 * pi * fc_lpf / fs;
n = -(N_filt-1)/2 : (N_filt-1)/2;
h = (sin(wc*n)./(pi*n)) .* hamming(N_filt)';
h((N_filt+1)/2) = wc/pi;

fprintf('正在進行 FDM 分頻解調與卷積濾波...\n');
% 分別濾除高頻與隔壁頻道的雜訊，並乘以 2 補償振幅
demod_signal_L = conv(demod_raw_L, h, 'same') * 2;
demod_signal_R = conv(demod_raw_R, h, 'same') * 2;

% 合併回 N x 2 的雙聲道矩陣供後續播放
demod_signal = [demod_signal_L, demod_signal_R];

% --- 5. 繪圖 ---
figure('Name', '10s Audio FDM Simulation', 'Color', 'w');

% 時域：顯示第 1 秒附近的 5 毫秒片段
view_range = round(1.0 * fs) : round(1.005 * fs);

% (1) 左聲道與 FDM 訊號對比
subplot(3,1,1);
plot(t(view_range)*1e3, mt(view_range, 1), 'b', 'LineWidth', 1.5); hold on;
% 畫出融合後的 FDM 傳輸訊號，使用半透明黑色以利觀察包絡線
plot(t(view_range)*1e3, st_fdm(view_range), 'k', 'Color', [0 0 0 0.3]); 
title('時域訊號放大 (1.0s - 1.005s) - 左聲道 vs FDM 傳輸訊號');
xlabel('時間 (ms)');
legend('左聲道原始音訊', '單一 FDM 傳輸訊號', 'Location', 'best');
grid on;

% (2) 右聲道與 FDM 訊號對比
subplot(3,1,2);
plot(t(view_range)*1e3, mt(view_range, 2), 'g', 'LineWidth', 1.5); hold on;
% 同樣畫出融合後的 FDM 傳輸訊號
plot(t(view_range)*1e3, st_fdm(view_range), 'k', 'Color', [0 0 0 0.3]);
title('時域訊號放大 (1.0s - 1.005s) - 右聲道 vs FDM 傳輸訊號');
xlabel('時間 (ms)');
legend('右聲道原始音訊', '單一 FDM 傳輸訊號', 'Location', 'best');
grid on;

% (3) 頻域：分析 FDM 訊號的單一頻譜 (觀察兩個獨立的峰值)
L_fft = 2^18;
ST_FDM_FFT = abs(fft(st_fdm(1:L_fft), L_fft)/L_fft); 
f_axis = fs*(0:L_fft/2)/L_fft;

subplot(3,1,3);
plot(f_axis/1e6, 2*ST_FDM_FFT(1:L_fft/2+1), 'r', 'LineWidth', 1.2);
title('FDM 調變頻譜 - 左聲道 (0.1MHz) 與 右聲道 (0.15MHz)'); 
xlabel('頻率 (MHz)'); 
% 放大 X 軸範圍，涵蓋 50kHz 到 200kHz
xlim([0.05, 0.20]); 
legend('FDM 混合訊號', 'Location', 'best');
grid on;

% --- 6. 播放音樂 ---
fprintf('正在還原音訊以供播放...\n');
audio_out = resample(demod_signal, fs_audio, fs);

% 正規化音量防止爆音 (找尋雙聲道中的全局最大值來做正規化)
audio_out = audio_out / max(abs(audio_out(:)));

% 播放解調後的聲音
fprintf('準備播放解調後的立體聲音樂...\n');
sound(audio_out, fs_audio);