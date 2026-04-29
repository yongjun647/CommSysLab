%% 1. 參數設定
Fs = 1.92e6;              % 系統取樣率 1.92 MHz
Ts = 1/Fs;
sim_time = 15;            % 模擬總長度：只擷取音檔前 15 秒
data_len = sim_time * Fs; % 總取樣點數
t = (0:data_len-1) * Ts;  % 時間軸 (1 x data_len 的橫向量)

% --- 頻率設定 ---
f_sub1 = 20e3;            % 子載波 1: 20 kHz
f_sub2 = 100e3;           % 子載波 2: 100 kHz
f_LO   = 500e3;           % 射頻載波: 500 kHz (AM 廣播頻段)

%% 2. 音訊前處理/Upsampling
disp('正在讀取並重取樣音檔，請稍候...');

% 讀取第一首歌 (給 s1)
[y1, fs_audio1] = audioread('music.mp3');
if size(y1, 2) > 1, y1 = sum(y1, 2)/2; end % 若為雙聲道，轉為單聲道
% 建立原本音訊的專屬時間軸，並使用 interp1 升頻 (Upsampling) 至 1.92 MHz
samples_1 = min(length(y1), sim_time * fs_audio1);
t_audio1 = (0:samples_1-1) / fs_audio1;
y1_full = y1(1:samples_1).';
m1 = interp1(t_audio1, y1_full, t, 'linear', 'extrap');
m1 = m1 / max(abs(m1));                    % 歸一化振幅至 [-1, 1]

% 讀取第二首歌 (給 s2)
[y2, fs_audio2] = audioread('audio2.wav');
if size(y2, 2) > 1, y2 = sum(y2, 2)/2; end % 若為雙聲道，轉為單聲道
% 使用 interp1 升頻 (Upsampling) 至 1.92 MHz
samples_2 = min(length(y2), sim_time * fs_audio2);
t_audio2 = (0:samples_2-1) / fs_audio2;
y2_full = y2(1:samples_2).';
m2 = interp1(t_audio2, y2_full, t, 'linear', 'extrap');
m2 = m2 / max(abs(m2));                    % 歸一化振幅至 [-1, 1]

disp('音檔處理完成！開始進行調變...');

%% 3. 產生 FDM 複數訊號
% 將音檔變成 AM 調幅的基頻訊號形式 (1 + 0.8*m)
s1_am = 1 + 0.8 * m1;
s2_am = 1 + 0.8 * m2;

% 子載波搬移
s1_cx = s1_am .* exp(1j * 2 * pi * f_sub1 * t);
s2_cx = s2_am .* exp(1j * 2 * pi * f_sub2 * t);
tx_complex = s1_cx + s2_cx; % 合成後的 I/Q 複數訊號

%% 4. [發射端 TX] 正交調變
I_t = real(tx_complex);
Q_t = imag(tx_complex);

% Mixer: s(t) = I*cos - Q*sin
tx_rf_real = I_t .* cos(2 * pi * f_LO * t) - Q_t .* sin(2 * pi * f_LO * t);
tx_rf_real = 0.8 * tx_rf_real / max(abs(tx_rf_real)); % 歸一化

%% 5. [接收端 RX] 正交解調
rx_rf_real = tx_rf_real; % 理想通道 (無雜訊)

% 乘上本機振盪器 (LO) 訊號
r_I_raw = rx_rf_real .* cos(2 * pi * f_LO * t);
r_Q_raw = rx_rf_real .* (-sin(2 * pi * f_LO * t));

% 通過LPF 濾除2*f_LO的高頻項 (截止頻率 200 kHz)
[b_rf, a_rf] = butter(3, 200e3/(Fs/2), 'low');
r_I_filtered = filtfilt(b_rf, a_rf, r_I_raw);
r_Q_filtered = filtfilt(b_rf, a_rf, r_Q_raw);

rx_raw = r_I_filtered + 1j * r_Q_filtered; % 還原複數訊號

%% 6. 基頻訊號還原與音訊降頻
disp('開始解調與降頻...');

% 擷取基頻用的 LPF (15 kHz)
[b_base, a_base] = butter(3, 15e3/(Fs/2), 'low');

% s1 解調 (20 kHz -> DC)
s1_base = rx_raw .* exp(-1j * 2 * pi * f_sub1 * t);
s1_demod = abs(filtfilt(b_base, a_base, s1_base));
s1_demod = s1_demod - mean(s1_demod); % 去除 DC

% s2 解調 (100 kHz -> DC)
s2_base = rx_raw .* exp(-1j * 2 * pi * f_sub2 * t);
s2_demod = abs(filtfilt(b_base, a_base, s2_base));
s2_demod = s2_demod - mean(s2_demod); % 去除 DC

% === 將解調後的訊號降頻回原本的音訊取樣率，以便播放 ===
% 建立 44.1kHz 的目標時間軸，並用 interp1 進行降頻
t_audio_out1 = (0 : (sim_time * fs_audio1) - 1) / fs_audio1;
t_audio_out2 = (0 : (sim_time * fs_audio2) - 1) / fs_audio2;

audio_out1 = interp1(t, s1_demod, t_audio_out1, 'linear', 'extrap');
audio_out2 = interp1(t, s2_demod, t_audio_out2, 'linear', 'extrap');

disp('模擬完成！正在繪圖...');

%% 7. 繪圖 (接收端 RF 訊號之頻譜圖與時域圖)
disp('開始繪製接收端 RF 訊號圖...');

% ---------------------------------------------------------
% (A) 頻譜圖 (Frequency Domain) - 使用 dB 刻度觀察旁波帶
% ---------------------------------------------------------
N = data_len;
% 建立頻率軸 (平移到中心為 0 Hz)
f_axis = linspace(-Fs/2, Fs/2 - Fs/N, N);

% 計算頻譜大小 (取絕對值並進行 fftshift)
Rx_RF_mag = abs(fftshift(fft(rx_rf_real))) / N;

% 建立繪圖視窗
figure('Name', '接收端 RF 訊號分析', 'Position', [150, 150, 900, 600]);

% 繪製 RF 頻譜圖
subplot(1,1,1);
plot(f_axis/1000, 20*log10(Rx_RF_mag + 1e-10), 'b');
title('接收端 RF 訊號頻譜圖');
xlabel('頻率 (kHz)');
ylabel('dB');
xlim([-1000 1000]);
grid on;

%% 8. 立體聲播放 (左耳 s1, 右耳 s2)
disp('準備進行立體聲播放...');

% 1. 確保兩個音檔都是直行向量 (Column vector)
audio_out1 = audio_out1(:);
audio_out2 = audio_out2(:);

% 2. 確保兩者長度完全一致 (避免 resample 時產生 1~2 個點的長度誤差導致無法合併)
min_len = min(length(audio_out1), length(audio_out2));
audio_out1 = audio_out1(1:min_len);
audio_out2 = audio_out2(1:min_len);

% 3. 合併成立體聲矩陣：第一行是左耳，第二行是右耳
stereo_out = [audio_out1, audio_out2];

% 4. 播放！
disp('請戴上雙聲道耳機');
disp('左耳：播放 s1 (目標音樂 1)');
disp('右耳：播放 s2 (目標音樂 2)');
sound(stereo_out, fs_audio1);