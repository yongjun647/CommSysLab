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

% --- 3. QM 調變 (Quadrature Multiplexing) ---
c_I = cos(2*pi*fc*t);      % 同相載波 (In-phase, 供左聲道使用)
c_Q = sin(2*pi*fc*t);      % 正交載波 (Quadrature, 供右聲道使用)

% 左聲道乘上 cos，右聲道乘上 sin，然後「相加」成一個單一通道的傳輸訊號
st_qm = mt(:, 1) .* c_I + mt(:, 2) .* c_Q; 

% --- 4. QM 解調與 FIR 濾波 ---
% 接收端將收到的單一訊號 st_qm，分別乘上本地的 cos 與 sin
demod_raw_L = st_qm .* c_I;
demod_raw_R = st_qm .* c_Q;

% FIR 濾波器設計
N_filt = 101;
fc_lpf = 15e3;            % 音訊截止頻率 15kHz
wc = 2 * pi * fc_lpf / fs;
n = -(N_filt-1)/2 : (N_filt-1)/2;
h = (sin(wc*n)./(pi*n)) .* hamming(N_filt)';
h((N_filt+1)/2) = wc/pi;

fprintf('正在進行正交解調與卷積濾波...\n');
% 分別濾除高頻，還原左右聲道，並乘以 2 補償振幅衰減
demod_signal_L = conv(demod_raw_L, h, 'same') * 2;
demod_signal_R = conv(demod_raw_R, h, 'same') * 2;

% 合併回 N x 2 的雙聲道矩陣供後續播放
demod_signal = [demod_signal_L, demod_signal_R];

% --- 5. 繪圖 ---
figure('Name', '10s Audio QM Simulation', 'Color', 'w');

% 時域：顯示第 1 秒附近的 5 毫秒片段
view_range = round(1.0 * fs) : round(1.005 * fs);

% (1) 左聲道與 QM 訊號對比
subplot(3,1,1);
plot(t(view_range)*1e3, mt(view_range, 1), 'b', 'LineWidth', 1.5); hold on;
% 注意：這裡畫的是融合後的單一傳輸訊號 st_qm
plot(t(view_range)*1e3, st_qm(view_range), 'r', 'Color', [1 0 0 0.3]); 
title('時域訊號放大 (1.0s - 1.005s) - 左聲道 vs QM 傳輸訊號');
xlabel('時間 (ms)');
legend('左聲道原始音訊', '單一 QM 傳輸訊號', 'Location', 'best');
grid on;

% (2) 右聲道與 QM 訊號對比
subplot(3,1,2);
plot(t(view_range)*1e3, mt(view_range, 2), 'g', 'LineWidth', 1.5); hold on;
% 注意：這裡一樣是畫 st_qm
plot(t(view_range)*1e3, st_qm(view_range), 'r', 'Color', [1 0 0 0.3]);
title('時域訊號放大 (1.0s - 1.005s) - 右聲道 vs QM 傳輸訊號');
xlabel('時間 (ms)');
legend('右聲道原始音訊', '單一 QM 傳輸訊號', 'Location', 'best');
grid on;

% (3) 頻域：分析 QM 訊號的單一頻譜
L_fft = 2^18;
ST_QM_FFT = abs(fft(st_qm(1:L_fft), L_fft)/L_fft); % 現在只需做一次 FFT
f_axis = fs*(0:L_fft/2)/L_fft;

subplot(3,1,3);
plot(f_axis/1e6, 2*ST_QM_FFT(1:L_fft/2+1), 'r', 'LineWidth', 1.2);
title('QM 調變頻譜中心 (0.1MHz) - 疊加雙聲道'); 
xlabel('頻率 (MHz)'); 
xlim([fc/1e6 - 0.05, fc/1e6 + 0.05]);
legend('QM 混合訊號', 'Location', 'best');
grid on;

% --- 6. 播放音樂 ---
fprintf('正在還原音訊以供播放...\n');
audio_out = resample(demod_signal, fs_audio, fs);

% 正規化音量防止爆音 (找尋雙聲道中的全局最大值來做正規化)
audio_out = audio_out / max(abs(audio_out(:)));

% 播放解調後的聲音
fprintf('準備播放解調後的立體聲音樂...\n');
sound(audio_out, fs_audio);