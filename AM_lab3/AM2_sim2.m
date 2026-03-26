%% 1. 參數設定
SR = 192e3;            % 取樣率 (192 kHz)
fc = 40e3;            % 載波頻率 (40 kHz)
Mod_Index = 0.8;      % 調變指數
Sim_Duration = 5;     % 模擬時長 (5 秒)
mp3_filename = 'music.mp3';
%% 2. 訊號來源 (音訊讀取)
% 使用 audioread 讀取音訊檔案 [cite: 5, 21]
[y_raw, file_fs] = audioread(mp3_filename); 

% 轉換為單聲道 (若音訊為雙聲道)
if size(y_raw, 2) > 1
    y_raw = mean(y_raw, 2);
end

% 根據 Sim_Duration 擷取特定長度的音訊 [cite: 21, 22]
% 計算所需樣本數：時長 * 檔案原始取樣率
num_samples = min(round(Sim_Duration * file_fs), length(y_raw));
y = y_raw(1:num_samples);

fprintf('成功讀取音訊檔案：%s\n', mp3_filename);
fprintf('檔案原始取樣率：%d Hz\n', file_fs);
%% 3. 發射端處理 (Transmitter)
% A. 音訊重取樣與正規化
y_resamp = resample(y, SR, file_fs);
y_norm = y_resamp / max(abs(y_resamp));

% B. 產生基頻包絡
% 此時 iq_base 是一條隨音訊起伏但永遠大於 0 的曲線
iq_base = (1 + Mod_Index * y_norm);

% C. 乘上載波產生震盪 (Passband Signal)
t = (0:length(iq_base)-1)' / SR;
A_c = 1;              % 假設 A_c = 1
tx_signal = A_c * iq_base .* cos(2 * pi * fc * t);

%% 4. 接收端 (SDR IQ Demodulator)
% --- Step A: 數位混頻 (Digital Mixing) ---
mix_i = tx_signal .* cos(2 * pi * fc * t);        % I 路：乘上 Cos
mix_q = tx_signal .* (-sin(2 * pi * fc * t));     % Q 路：乘上 -Sin

% --- Step B: 低通濾波 (LPF) ---
% 濾除 2*fc 的高頻成分，留下基頻 I/Q
[b, a] = butter(5, (fc*0.5)/(SR/2));
I_base = filter(b, a, mix_i);
Q_base = filter(b, a, mix_q);

% --- Step C: (Envelope Extraction) ---
% 乘 2 是因為混頻過程中能量會折半
iq_complex = I_base + 1i * Q_base;
rx_env_iq = 2 * abs(iq_complex);

% --- Step D: 直流濾除 ---
% 減去平均值，找回原始訊息 m(t)
rx_audio = rx_env_iq - mean(rx_env_iq);
rx_final = rx_audio / max(abs(rx_audio));

%% 5. 音訊輸出
fprintf('正在播放解調後的音訊...\n');
soundsc(rx_final, SR);

%% 6. 繪圖與分析
figure('Color', 'w', 'Position', [100, 100, 900, 700]);

% SDR 內部的正交分量 (I/Q)
subplot(3,1,1);
plot(t*1000, I_base, 'g', 'DisplayName', 'I (In-phase)');
hold on;
plot(t*1000, Q_base, 'm', 'DisplayName', 'Q (Quadrature)');
title('SDR 內部的正交分量 (I/Q)');
xlabel('時間 (ms)'); ylabel('振幅');
legend; grid on; xlim([10, 15]);

% 時域波形：觀察震盪與 Envelope
subplot(3,1,2);
plot(t*10, tx_signal, 'Color', [0.7 0.7 0.7], 'DisplayName', 'Carrier Oscillation');
hold on;
plot(t*10, iq_base, 'r', 'LineWidth', 2, 'DisplayName', 'iq\_base (Envelope)');
title('AM 時域模擬');
xlabel('時間 (ms)'); ylabel('振幅');
legend; grid on; xlim([1 50]);

% 頻域分析
subplot(3,1,3);
L = length(tx_signal);
f = SR*(0:(L/2))/L;
Y = fft(tx_signal);
P1 = abs(Y(1:L/2+1)/L); P1(2:end-1) = 2*P1(2:end-1);
plot(f/1000, 10*log10(P1 + 1e-12), 'Color', [0 0.447 0.741]);
title('AM 頻域模擬');
xlabel('頻率 (kHz)'); ylabel('功率 (dB)');
grid on; xlim([0 80]); % 顯示到 80kHz