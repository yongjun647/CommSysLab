%% QPSK Transmitter for SDR
clc; clear; close all;

%% 1. 參數設定 (System Parameters)
SR = 122.88e6;
Upsampling_Factor = 64;
Rolloff = 0.5;
FilterSpan = 64;

% 載波與功率設定
CenterFreq = 433;    % MHz
TxGain = -20;        % dBm

%% 2. 動態產生資料封包 (Bit Generation with Length Field)
% 上限 255 個字元
msg_str = 'Hello world! This is a fully automatic dynamic packet test 2026.';
fprintf('輸入字串: "%s"\n', msg_str);

% A. 將字串轉為 7-bit ASCII 二進制
char_len = length(msg_str);
if char_len > 255
    error('字串過長!!');
end
msg_ascii = double(msg_str);
msg_bits = de2bi(msg_ascii, 7, 'left-msb')';
payload_raw = msg_bits(:); % 真正的字串 bit 串流

% B. 產生 8-bit 長度指示器 (Length Field):將字元數轉為 8-bit 二進制
length_bits = de2bi(char_len, 8, 'left-msb')';

% C. Frame Header: Barker Code (26 bits)
barker_13 = [1 1 1 1 1 0 0 1 1 0 1 0 1]';
header_bits = [barker_13; barker_13];

% D. 擾碼器 (Scrambler) - 只對 Payload 擾碼，維持 Header 與 Length 可讀性
scrambler = comm.Scrambler(2, [1 1 1 0 1], 'InitialConditions', [0 0 0 0]);
payload_scrambled = scrambler(payload_raw);

% E. 組合 Frame 核心元素 (未做奇偶對齊前)
% 結構 : [ Header (26b) | Length (8b) | Scrambled Payload (Nb) ]
tx_bits_pre = [header_bits; length_bits; payload_scrambled];

% F. 為了 QPSK 串並轉換，總位元數必須是偶數
if mod(length(tx_bits_pre), 2) ~= 0
    % 如果是奇數，在封包最後面補 1 bit Dummy bit
    tx_bits = [tx_bits_pre; 0];
else
    tx_bits = tx_bits_pre;
end

%% 3. QPSK 調變
% 串列轉並列 (N/2 x 2 矩陣)
bits_reshaped = reshape(tx_bits, 2, []).';

% 二進制轉十進制索引
sym_idx = bits_reshaped(:, 1) * 2 + bits_reshaped(:, 2);

% 星座圖查找表 (Gray Mapping + pi/4 offset)
constellation_lut = [exp(1j*pi/4); exp(1j*3*pi/4); exp(1j*7*pi/4); exp(1j*5*pi/4)];

% 符號映射
symbols = constellation_lut(sym_idx + 1);

%% 4. 脈衝整形濾波 (Pulse Shaping) - Root Raised Cosine
rrc_filter = rcosdesign(Rolloff, FilterSpan, Upsampling_Factor, 'sqrt');
tx_signal_filtered = upfirdn(symbols, rrc_filter, Upsampling_Factor);

% 調整訊號振幅以符合 DAC 範圍 (+-1)
scale_factor = max(abs([real(tx_signal_filtered); imag(tx_signal_filtered)]));
tx_signal_norm = tx_signal_filtered / scale_factor * 0.8;

% 轉成 YTTEK API 需要的格式 (Row Vector)
xk = tx_signal_norm.';

% 將封包重複多次以形成長訊號流方便接收端擷取
xk = repmat(xk, 1, 100);

%% 5. SDR 硬體發射 (Hardware Transmission)
fprintf('\n--- 開始設定 SDR 硬體 ---\n');
try
    % 呼叫硬體 API 進行設定
    LO_CHANGE(0, CenterFreq, CenterFreq);
    set_TX_power([0 TxGain]);
    fprintf('開始發射 QPSK 訊號...\n');
    
    tx_data_sdr = repmat(xk, 1, 1);
    TX_start(tx_data_sdr, 0);
    
    fprintf('SDR 正在發射中。請開啟接收端程式碼進行自動解調。\n');
    fprintf('若要停止，請在 Command Window 輸入: TX_close\n');
catch
    warning('SDR 硬體未連接，僅完成數位訊號模擬。');
end