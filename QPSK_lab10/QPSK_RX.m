%{
%% QPSK Receiver for SDR
clc; clear; close all;

%% 1. 參數設定 (System Parameters)
SR = 122.88e6;             % Sample Rate
Upsampling_Factor = 64;
Rolloff = 0.5;
FilterSpan = 64;
CenterFreq = 433;
RxGain = -20;
RxTime = 0.008;            % 錄取時間 8ms，確保裝得下極長字串

HeaderLength_Bits = 26;    % 固定的 Header 長度
LengthField_Bits = 8;      % 固定的長度指示器位元數

%% 2. SDR 硬體接收 (Hardware Reception)
fprintf('\n--- 開始設定 SDR RX ---\n');
try
    LO_CHANGE(0, CenterFreq, CenterFreq);
    set_RX_Ref_Level_ELSDR([0 RxGain]);
    RxLen = round(RxTime * SR);
    
    rx_data_raw = RX(1, RxLen);
    if size(rx_data_raw, 1) == 2
        rx_signal = rx_data_raw(1,:) + 1j*rx_data_raw(2,:);
    else
        rx_signal = rx_data_raw;
    end
    rx_signal = double(rx_signal(:));
    rx_signal = rx_signal - mean(rx_signal);
catch
    warning('SDR 連接失敗，使用模擬雜訊測試...');
    RxLen = round(RxTime * SR);
    rx_signal = (randn(RxLen, 1) + 1j*randn(RxLen, 1)) * 0.1;
end

%% 3. 脈衝整形濾波 (RRC Matched Filter)
rrc_filter = rcosdesign(Rolloff, FilterSpan, Upsampling_Factor, 'sqrt');
rx_filtered = conv(rx_signal, rrc_filter, 'same');

%% 4. 同步 (Frame Synchronization & Timing Localization)
% ...
% % --- (Matched Filtering & Cross-Correlation) ---
% ...

% 拓寬管路：預抓 2000 個 symbols 的暫時大區塊，從中動態解析長度
max_look_symbols = 2000;
samples_to_extract = max_look_symbols * Upsampling_Factor;
if start_idx + samples_to_extract - 1 > length(rx_filtered)
    samples_to_extract = length(rx_filtered) - start_idx + 1;
end
frame_signal_oversampled = rx_filtered(start_idx : start_idx + samples_to_extract - 1);

%% 5. 下取樣與純靜態相位校正
frame_symbols_raw = frame_signal_oversampled(1 : Upsampling_Factor : end);

rx_header_syms = frame_symbols_raw(1 : length(header_symbols));
phase_diff_vec = angle(rx_header_syms .* conj(header_symbols));
estimated_phase_error = mean(phase_diff_vec);

rx_symbols_sync = frame_symbols_raw * exp(-1j * estimated_phase_error);

%% 6. 解調第一階段：讀取 8-bit 長度欄位 (Decode Length Field)
% ...
% 解調第二階段：根據解出的長度「動態裁切」並解析字串
% 根據解出的長度裁切並解析字串
% ...

fprintf('\n----------------------------------------\n');
fprintf(' 【解碼成功】 訊息內容:\n');
fprintf('"%s"\n', rx_str);
fprintf('----------------------------------------\n');


%% 7. 繪圖
figure('Name', 'Constellation ', 'Color', 'w', 'Position', [100, 150, 900, 450]);
max_val = max(abs([real(rx_symbols_final); imag(rx_symbols_final)])) * 1.2;

% 圖 1：完全未校正的原始 Symbols
subplot(1,2,1);
plot(real(frame_symbols_raw(1:total_frame_symbols)), imag(frame_symbols_raw(1:total_frame_symbols)), 'r.', 'MarkerSize', 8);
hold on; xline(0, '--k'); yline(0, '--k');
title('1. Before Phase Sync (Raw)', 'FontSize', 12);
axis square; grid on; xlim([-max_val max_val]); ylim([-max_val max_val]);

% 圖 2：相位同步後的 Symbols
subplot(1,2,2);
plot(real(rx_symbols_final), imag(rx_symbols_final), 'b.', 'MarkerSize', 8);
hold on; xline(0, '--k'); yline(0, '--k');
title(['2. After Static Sync (Symbols: ', num2str(total_frame_symbols), ')'], 'FontSize', 12);
axis square; grid on; xlim([-max_val max_val]); ylim([-max_val max_val]);
%}

%% QPSK Receiver for SDR
clc; clear; close all;

%% 1. 參數設定 (System Parameters)
SR = 122.88e6;             % Sample Rate
Upsampling_Factor = 64;
Rolloff = 0.5;
FilterSpan = 64;
CenterFreq = 433;
RxGain = -20;
RxTime = 0.008;            % 錄取時間 8ms，確保裝得下極長字串
HeaderLength_Bits = 26;    % 固定的 Header 長度
LengthField_Bits = 8;      % 固定的長度指示器位元數

%% 2. SDR 硬體接收 (Hardware Reception)
fprintf('\n--- 開始設定 SDR RX ---\n');
try
    LO_CHANGE(0, CenterFreq, CenterFreq);
    set_RX_Ref_Level_ELSDR([0 RxGain]);
    RxLen = round(RxTime * SR);
    
    rx_data_raw = RX(1, RxLen);
    if size(rx_data_raw, 1) == 2
        rx_signal = rx_data_raw(1,:) + 1j*rx_data_raw(2,:);
    else
        rx_signal = rx_data_raw;
    end
    rx_signal = double(rx_signal(:));
    rx_signal = rx_signal - mean(rx_signal);
catch
    warning('SDR 連接失敗，使用模擬雜訊與標準訊號進行測試...');
    RxLen = round(RxTime * SR);
    % 產生測試訊號以利程式碼在沒接 SDR 時也能跑通
    rx_signal = (randn(RxLen, 1) + 1j*randn(RxLen, 1)) * 0.1;
end

%% 3. 脈衝整形濾波 (RRC Matched Filter)
rrc_filter = rcosdesign(Rolloff, FilterSpan, Upsampling_Factor, 'sqrt');
rx_filtered = conv(rx_signal, rrc_filter, 'same');

%% 4. 同步 (Frame Synchronization & Timing Localization)
fprintf('--- 開始進行時間與相位同步 ---\n');

% 建立與發射端完全相同的已知 Header 符號
barker_13 = [1 1 1 1 1 0 0 1 1 0 1 0 1]';
header_bits = [barker_13; barker_13];
lut = [exp(1j*pi/4); exp(1j*3*pi/4); exp(1j*7*pi/4); exp(1j*5*pi/4)];

header_sym_idx = header_bits(1:2:end)*2 + header_bits(2:2:end);
header_symbols = lut(header_sym_idx + 1);

header_waveform = zeros(length(header_symbols) * Upsampling_Factor, 1);
header_waveform(1:Upsampling_Factor:end) = header_symbols;
header_waveform = conv(header_waveform, rrc_filter, 'same');
L_header = length(header_waveform);

% 互相關與能量正規化計算
matched_coeff = flip(conj(header_waveform));
rx_corr = filter(matched_coeff, 1, rx_filtered);
window_ones = ones(L_header, 1);
rx_power = abs(rx_filtered).^2;
rx_energy_moving = filter(window_ones, 1, rx_power);
header_energy_const = sum(abs(header_waveform).^2);

timing_metric = (abs(rx_corr).^2) ./ (rx_energy_moving * header_energy_const + 1e-10);
[max_metric, peak_idx] = max(timing_metric);

Sync_Threshold = 0.35; % SDR 環境實測彈性調整
fprintf('[時間同步] 最大指標 (Metric): %.4f\n', max_metric);

start_idx = peak_idx - L_header + 1;
if start_idx < 1, start_idx = 1; end
fprintf('  -> 偵測到 Frame 起點 Index: %d\n', start_idx);

% 拓寬管路：預抓 2000 個 symbols 的暫時大區塊，從中動態解析長度
max_look_symbols = 2000;
samples_to_extract = max_look_symbols * Upsampling_Factor;
if start_idx + samples_to_extract - 1 > length(rx_filtered)
    samples_to_extract = length(rx_filtered) - start_idx + 1;
end
frame_signal_oversampled = rx_filtered(start_idx : start_idx + samples_to_extract - 1);

%% 5. 下取樣與純靜態相位校正
frame_symbols_raw = frame_signal_oversampled(1 : Upsampling_Factor : end);
rx_header_syms = frame_symbols_raw(1 : length(header_symbols));
phase_diff_vec = angle(rx_header_syms .* conj(header_symbols));
estimated_phase_error = mean(phase_diff_vec);
fprintf('[相位同步] 偵測到靜態相位偏移: %.2f 度\n', estimated_phase_error * 180/pi);

rx_symbols_sync = frame_symbols_raw * exp(-1j * estimated_phase_error);

%% 6. 解調第一階段：讀取 8-bit 長度欄位 (Decode Length Field)
% 全量解調 I/Q 判決法
rx_bits_raw = zeros(length(rx_symbols_sync) * 2, 1);
for k = 1:length(rx_symbols_sync)
    r_real = real(rx_symbols_sync(k));
    r_imag = imag(rx_symbols_sync(k));
    
    if r_real >= 0 && r_imag >= 0      % Q1 -> 00
        bits = [0; 0];
    elseif r_real < 0 && r_imag >= 0   % Q2 -> 01
        bits = [0; 1];
    elseif r_real < 0 && r_imag < 0    % Q3 -> 11
        bits = [1; 1];
    else                               % Q4 -> 10
        bits = [1; 0];
    end
    rx_bits_raw(2*k-1 : 2*k) = bits;
end

% 檢查 Header 錯誤率
rx_header = rx_bits_raw(1:HeaderLength_Bits);
num_err = sum(abs(header_bits - rx_header));
fprintf('Header BER: %.4f (%d bit errors)\n', num_err / length(header_bits), num_err);

% 提取動態長度欄位 (假設接在 Header 後方 8 bits)
len_start_bit = HeaderLength_Bits + 1;
len_end_bit = HeaderLength_Bits + LengthField_Bits;

if length(rx_bits_raw) >= len_end_bit
    length_bits = rx_bits_raw(len_start_bit : len_end_bit);
    % 將二進制轉換回十進制整數 (代表文字的字元數)
    char_length = length_bits' * [128 64 32 16 8 4 2 1]'; 
    fprintf('[動態解析] 偵測到內部 Payload 包含 %d 個字元\n', char_length);
else
    char_length = 0;
    warning('接收資料過短，無法解析長度欄位。');
end

%% 解調第二階段：根據解出的長度「動態裁切」並解析字串
if char_length > 0 && char_length < 200 % 設定合理字串上限保護
    msg_len_bits = char_length * 7;      % 每個 ASCII 佔 7 bits
    
    % 計算實際 Payload 的起迄點
    payload_start_bit = len_end_bit + 1;
    payload_end_bit = payload_start_bit + msg_len_bits - 1;
    
    if length(rx_bits_raw) >= payload_end_bit
        rx_payload_scrambled = rx_bits_raw(payload_start_bit : payload_end_bit);
        
        % 解擾碼器 (Descrambler)
        descrambler = comm.Descrambler(2, [1 1 1 0 1], 'InitialConditions', [0 0 0 0]);
        rx_payload_descrambled = descrambler(rx_payload_scrambled);
        
        % 還原為 ASCII 字串
        rx_msg_matrix = reshape(rx_payload_descrambled, 7, []).';
        rx_ascii = rx_msg_matrix * [64 32 16 8 4 2 1]';
        rx_str = char(rx_ascii);
    else
        rx_str = '[錯誤] 訊號長度不足以解調預期的字串內容';
    end
else
    rx_str = '[錯誤] 解析出的字串長度異常，可能同步失敗或雜訊過大';
end

fprintf('\n----------------------------------------\n');
fprintf(' 【解碼成功】 訊息內容:\n');
fprintf('"%s"\n', rx_str);
fprintf('----------------------------------------\n');

%% 7. 星座圖繪製 (診斷硬體訊號用)
figure('Name', 'SDR RX Debug Panel', 'Color', 'w');
subplot(1,2,1);
plot(real(frame_symbols_raw), imag(frame_symbols_raw), 'r.', 'MarkerSize', 6); hold on;
xline(0, '--k'); yline(0, '--k'); axis square; grid on;
title('1. Before Phase Sync');

subplot(1,2,2);
plot(real(rx_symbols_sync), imag(rx_symbols_sync), 'b.', 'MarkerSize', 6); hold on;
xline(0, '--k'); yline(0, '--k'); axis square; grid on;
title('2. After Phase Sync (Decoded)');