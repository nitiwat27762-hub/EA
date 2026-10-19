//+------------------------------------------------------------------+
//|                                       Seven_Lines_Counter_EA.mq5 |
//|      Fast Mean-Reversion Z-Score EA for XAUUSD (Indicator v8.82)  |
//+------------------------------------------------------------------+
//
// 🎯 นิยามระบบ (v12)
//  ค่า Z ที่สุดขั้วเกินจริงมักถูกดีดกลับเสมอ (แม้เป็นเทรนด์จริง) → สวนกลับอย่างเดียว ครั้งละ 1 ไม้
//  (ประวัติการเปลี่ยนแปลงทุกเวอร์ชันอยู่ใน README.md)
//
// 📐 Z-Score (TF ของ Z, 20 แท่ง, รวมแท่งปัจจุบันที่ราคา Bid)
//  • Z_reg = (ราคา − เส้นถดถอยเชิงเส้น) / max(StdDev รอบเส้นถดถอย, 0.5 × StdDev ของส่วนต่างราคาต่อแท่ง)
//  • Z_SMA = (ราคา − SMA20) / StdDev20
//
// 📋 ตรรกะการเข้าไม้ — ตรวจ T3 → T2 → T1, เกณฑ์เดียวกันทั้ง SELL (+Z) / BUY (−Z)
//  • T3: Z ตัวใดตัวหนึ่ง > 3.0 → ยิงทันที (Lot 0.03)
//  • T2: Z ทั้งคู่ > 2.8 + ไม่มีค่าสุดขั้วใหม่ 5 วิ + ยังอยู่ในโซน (Lot 0.02)
//  • T1: Z ทั้งคู่ > 2.3 + ไม่มีค่าสุดขั้วใหม่ 15 วิ + ยังอยู่ในโซน (Lot 0.01)
//    ลดระดับ = ใช้เวลารอของระดับใหม่ (นับจากค่าสุดขั้วล่าสุด), Z ตัวใดต่ำกว่า T1 → ยกเลิกแล้วหาสัญญาณใหม่
//  • ห้ามเฝ้า/เข้าไม้: นาทีแรก + 2 นาทีสุดท้ายของแท่ง, ข่าว USD High ±5 นาที (ไม้ที่ถืออยู่รันต่อ)
//  • ตัวกรองตอนยิง: เวลาตลาด + สเปรด
//  • Cool down: ชน SL ของ T3 1 ครั้ง / T2 2 ครั้งติด → พัก 30 นาที (คืนค่าจากประวัติเมื่อรีสตาร์ท)
//
// 📋 ตรรกะการจัดการไม้
//  • SL = High (SELL) / Low (BUY) ของแท่ง ณ ตอนเปิดไม้ ± 1,000 จุด (T3 ± 3,000), TP 30,000 จุด
//  • กำไรถึง 10,000 → เปิดโล่ไล่จี้ (ห่าง 8,000 ขยับทุก 5 วิ) แล้วปล่อยให้โล่ทำงาน
//  • ยังไม่ถึงโล่: กำไรคืนเกิน 75% จากกำไรสูงสุด (สูงสุด ≥ 2,000) → ตัดจบ / ครบ 1,500 วิ → ตัดจบ
//  • ห้ามเข้า 1 ชม.แรกหลังตลาดเปิดสัปดาห์ / ปิดทุกไม้ 30 นาทีก่อนตลาดปิดสัปดาห์
//
// 🧪 Tick Replay (บนกราฟ, ไม่ใช่ Strategy Tester)
//  • เล่นซ้ำ tick จริงย้อนหลังด้วยกติกาเดียวกับ EA (รวมตัวกรองข่าว) → มาร์กบนกราฟ + สรุปบน Dashboard
//  (เส้นบริบท VWAP / Keltner / TF ใหญ่ / วันก่อน / EMA ยาว แยกไปอยู่ใน Indicators/Seven_Lines_Context_Ind.mq5)
//
// ⚡ การประหยัด CPU
//  • Z: แคชผลรวมของแท่งที่ปิดแล้ว คำนวณใหม่เฉพาะตอนขึ้นแท่งใหม่ (ต่อ Tick ไม่กี่บรรทัดคณิต)
//  • จัดการไม้ / Dashboard / เส้น ทำบน OnTimer 1 วินาที, นับ SL ติดต่อกันผ่าน OnTradeTransaction
//  • Dashboard เขียนเฉพาะเมื่อข้อความเปลี่ยน, ไม่วาดอะไรใน Tester แบบไม่เปิด Visual
//
#property copyright   "Commander's Quant System"
#property version     "12.20"
#property description "สวนกลับค่า Z ผิดปกติที่ควรดีดกลับเร็ว สำหรับ XAUUSD (บัญชี Hedging)"

#include <Trade\Trade.mqh>

//====================================================================
// 🎛️ INPUT PARAMETERS
//====================================================================
input group "=== 1. Z-Score & จุดเข้า (สวนกลับ, เกณฑ์เดียวกันทั้ง SELL / BUY) ==="
input ENUM_TIMEFRAMES InpZ_Timeframe       = PERIOD_M15; // Timeframe ที่ใช้คำนวณ Z
input int             InpZ_Period          = 20;         // จำนวนแท่งของ SMA / StdDev
input double          InpT1_Z              = 2.30;       // T1: Z_reg และ Z_SMA ทั้งคู่ > ค่านี้ (SELL +Z / BUY −Z)
input int             InpT1_Sec            = 15;         // T1: ยิงเมื่อไม่มีค่าสุดขั้วใหม่ครบกี่วินาที
input double          InpT2_Z              = 2.80;       // T2: Z_reg และ Z_SMA ทั้งคู่ > ค่านี้
input int             InpT2_Sec            = 5;          // T2: ยิงเมื่อไม่มีค่าสุดขั้วใหม่ครบกี่วินาที
input double          InpT3_Z              = 3.00;       // T3: Z ตัวใดตัวหนึ่ง > ค่านี้ → ยิงทันที
input double          InpNoNewExtEps       = 0.01;       // Z ต้องเกินค่าสุดขั้วเดิมเท่านี้ถึงนับเป็นค่าใหม่
input double          InpSigmaFloorMult    = 0.50;       // ตัวหาร Z ต้องไม่น้อยกว่า ค่านี้ × StdDev ของการเปลี่ยนแปลงราคาต่อแท่ง

input group "=== 2. ออเดอร์ ==="
input double          InpLot               = 0.01;       // Lot ของ T1
input double          InpTierLotStep       = 0.01;       // Lot เพิ่มต่อระดับ (T2 = Lot+step, T3 = Lot+2·step)
input double          InpTP_Pts            = 30000.0;    // Take Profit (จุด)
input double          InpSLBeyond_Pts      = 1000.0;     // T1 / T2: SL = High (SELL) / Low (BUY) ของแท่ง (TF ของ Z) ณ ตอนเปิดไม้ ± ระยะนี้ (จุด)
input double          InpSLBeyondT3_Pts    = 3000.0;     // T3: SL = High / Low ของแท่ง ± ระยะนี้ (จุด)
input double          InpSlippage_Pts      = 300.0;      // Slippage สูงสุดตอนส่งคำสั่ง (จุด)
input long            InpMagic             = 880100;     // Magic Number
input string          InpOrderComment      = "7L-CNT";   // คอมเมนต์ออเดอร์ (ต่อท้ายด้วยระดับ T1-T3 ใช้คืนค่า Cool down)

input group "=== 3. ไล่จี้กำไร ==="
input double          InpTrailStart_Pts    = 10000.0;    // เริ่มไล่จี้เมื่อกำไรถึง (จุด)
input double          InpTrailDist_Pts     = 8000.0;     // ระยะโล่ห่างจากราคา (จุด)
input int             InpTrailInterval_Sec = 5;          // ขยับโล่ทุกกี่วินาที (หลังเริ่มไล่จี้แล้ว)

input group "=== 4. ตัดจบ / เวลาในแท่ง ==="
input int             InpQuickWindow_Sec   = 1500;       // ทุกไม้ต้องเข้าระบบไล่จี้ภายในกี่วินาที ไม่งั้นตัดจบ (0 = ปิด)
input double          InpGiveback_Pct      = 75.0;       // ยังไม่ถึงโล่: กำไรคืนเกินกี่ % จากกำไรสูงสุด → ตัดจบ (0 = ปิด)
input double          InpGivebackMinPeak_Pts = 2000.0;   // ใช้กฎคืนกำไรเมื่อกำไรสูงสุดถึงอย่างน้อยกี่จุด
input int             InpBarStartDelay_Sec = 60;         // ห้ามเฝ้า / เปิดไม้ ช่วงกี่วินาทีแรกของแท่ง (TF ของ Z)
input int             InpBarEndBlock_Sec   = 120;        // ห้ามเฝ้า / เปิดไม้ ช่วงกี่วินาทีสุดท้ายก่อนปิดแท่ง (0 = ปิด)

input group "=== 5. Cool down ==="
input int             InpCoolT2_SL         = 2;          // ชน SL ของ T2 ติดต่อกันกี่ครั้ง → เริ่มพัก (0 = ไม่นับ)
input int             InpCoolT3_SL         = 1;          // ชน SL ของ T3 ติดต่อกันกี่ครั้ง → เริ่มพัก (0 = ไม่นับ)
input int             InpCooldown_Min      = 30;         // พักกี่นาที

input group "=== 6. ตัวกรองทั่วไป ==="
input double          InpMaxSpread_Pts     = 800.0;      // สเปรดสูงสุดที่ยอมให้เข้าไม้ (จุด)
input int             InpNoTradeAfterOpen_Min = 60;      // ห้ามเข้าไม้หลังตลาดเปิดสัปดาห์ (นาที)
input int             InpCloseBeforeClose_Min = 30;      // ปิดทุกไม้ก่อนตลาดปิดสัปดาห์ (นาที)
input bool            InpNewsFilter        = true;       // งดเฝ้า / เข้าไม้ช่วงข่าว High (ไม้ที่ถืออยู่รันต่อ, ใช้ไม่ได้ใน Tester)
input int             InpNewsBlock_Min     = 5;          // งดก่อน / หลังเวลาข่าวออกกี่นาที
input string          InpNewsCurrency      = "USD";      // สกุลเงินของข่าว (กรอง + แสดง)

input group "=== 7. การแสดงผล ==="
input bool            InpShowDashboard     = true;       // แสดง Dashboard
input bool            InpShowZLines        = true;       // แสดงเส้นแนวนอนระดับ Z ชุด Regression
input bool            InpShowSmaZLines     = true;       // แสดงเส้นแนวนอนระดับ Z ชุด SMA20 (เปรียบเทียบ)
input bool            InpShow7Lines        = true;       // วาดเส้น 7 เส้น (คำนวณในตัว EA บน TF ของกราฟ)
input int             InpFastPeriod        = 10;         // Fast Period ของเส้น L1-L5
input int             InpLinesBars         = 200;        // จำนวนแท่งย้อนหลังที่วาดเส้น 7 เส้น
input bool            InpShowLineMain      = true;       // เส้น 7 เส้น: แสดง Main (SMA)
input bool            InpShowLineFast      = false;      // เส้น 7 เส้น: แสดงเส้นเร็ว L1-L6 (EMA / LWMA / HMA / LSMA / ALMA / Kinematic)
input bool            InpShowLiveZ         = true;       // แสดงป้ายค่า Z สด ณ ราคาปัจจุบัน
input int             InpLiveZFontSize     = 11;         // ขนาดตัวอักษรป้าย Z สด
input int             InpLiveZOffsetPx     = 10;         // ระยะห่างป้าย Z สดจากขอบขวาของกราฟ (พิกเซล)
input bool            InpShowBarZ          = true;       // แสดงป้ายค่า Z บนแท่งที่ Z ถึงเกณฑ์
input int             InpBarZBars          = 2000;       // จำนวนแท่งย้อนหลัง (TF ของ Z) ที่แสดงป้าย (สูงสุด 20,000)
input int             InpBarZFontSize      = 8;          // ขนาดตัวอักษรป้าย Z บนแท่ง
input double          InpBarZOffset_Pts    = 300.0;      // ระยะห่างป้ายจากไส้เทียน (จุด)
input bool            InpShowEntryMarks    = true;       // มาร์กจุดเปิดไม้ + ระยะห่างถึงปลายไส้เทียน
input bool            InpShowReplay        = true;       // Tick Replay: จำลองไม้ย้อนหลังจาก tick จริง + ผลแต่ละไม้
input int             InpReplayDays        = 10;         // Tick Replay: ย้อนหลังกี่วัน (1-60)
input bool            InpShowReplayBlocked = true;       // Tick Replay: มาร์กสัญญาณที่ถูกตัวกรองทิ้ง
input bool            InpShowNewsHistory   = true;       // แสดงช่วงข่าวบนกราฟ (ใช้ไม่ได้ใน Tester)
input bool            InpNewsIncludeMedium = false;      // แสดงข่าวระดับ Medium บนกราฟด้วย (ไม่ใช้กรอง)

input group "=== 8. สี ==="
input color           InpClrMain           = clrGold;           // เส้น Main (SMA)
input color           InpClrL1             = clrDeepSkyBlue;    // เส้น L1 (EMA)
input color           InpClrL2             = clrDodgerBlue;     // เส้น L2 (LWMA)
input color           InpClrL3             = clrMagenta;        // เส้น L3 (HMA)
input color           InpClrL4             = clrHotPink;        // เส้น L4 (LSMA)
input color           InpClrL5             = clrMediumSeaGreen; // เส้น L5 (ALMA)
input color           InpClrL6             = clrOrange;         // เส้น L6 (Kinematic)
input color           InpClrZCenter        = clrGold;           // เส้นแนวนอน: เส้นกลาง Z = 0
input color           InpClrZSellLine      = clrOrangeRed;      // เส้นแนวนอน: ระดับ SELL
input color           InpClrZBuyLine       = clrAqua;           // เส้นแนวนอน: ระดับ BUY
input color           InpClrSmaCenter      = clrDarkKhaki;      // เส้นแนวนอน SMA20: เส้นกลาง Z = 0
input color           InpClrSmaSellLine    = clrLightSalmon;    // เส้นแนวนอน SMA20: ระดับ SELL
input color           InpClrSmaBuyLine     = clrPaleTurquoise;  // เส้นแนวนอน SMA20: ระดับ BUY
input color           InpClrLiveSell       = clrOrangeRed;      // ป้าย Z สด: ถึงเกณฑ์ SELL
input color           InpClrLiveBuy        = clrDeepSkyBlue;    // ป้าย Z สด: ถึงเกณฑ์ BUY
input color           InpClrLiveNear       = clrGold;           // ป้าย Z สด: ใกล้เกณฑ์
input color           InpClrLiveNormal     = clrSilver;         // ป้าย Z สด: ปกติ
input color           InpClrBarZSell       = clrOrangeRed;      // ป้าย Z บนแท่ง: ฝั่ง SELL (เหนือแท่ง)
input color           InpClrBarZBuy        = clrDeepSkyBlue;    // ป้าย Z บนแท่ง: ฝั่ง BUY (ใต้แท่ง)
input color           InpClrBarZOther      = clrGray;           // ป้าย Z บนแท่ง: ถึงเกณฑ์ไม่ครบตามเงื่อนไขเข้าไม้
input color           InpClrEntrySell      = clrRed;            // มาร์กจุดเปิด SELL
input color           InpClrEntryBuy       = clrLime;           // มาร์กจุดเปิด BUY
input color           InpClrEntryGap       = clrYellow;         // เส้นประ + ตัวเลขระยะห่างถึงปลายไส้
input color           InpClrSimSell        = clrViolet;         // มาร์กจำลอง: SELL
input color           InpClrSimBuy         = clrPaleGreen;      // มาร์กจำลอง: BUY
input color           InpClrSimWin         = clrLimeGreen;      // มาร์กจำลอง: เส้นเข้า→ออก ไม้กำไร
input color           InpClrSimLoss        = clrTomato;         // มาร์กจำลอง: เส้นเข้า→ออก ไม้ขาดทุน
input color           InpClrSimBlocked     = clrDimGray;        // มาร์กจำลอง: สัญญาณที่ถูกตัวกรองทิ้ง
input color           InpClrSimCool        = clrDeepPink;       // มาร์กจำลอง: จุดเริ่ม Cool down
input color           InpClrNewsLine       = clrMediumPurple;   // เส้นเวลาข่าว
input color           InpClrNewsZone       = C'45,35,70';       // แถบแท่งข่าว

//====================================================================
// 🔒 INTERNAL
//====================================================================
#define TS_OPEN       0
#define TS_WAIT_OPEN  1
#define TS_CLOSING    2
#define TS_CLOSED     3

const string OBJ_PREFIX     = "7LCEA_";
const string LINE_MAIN      = "7LCEA_MAIN";
const string LINE_SELL      = "7LCEA_SELL_Z";
const string LINE_BUY       = "7LCEA_BUY_Z";
const string LABEL_LIVE_Z   = "7LCEA_LIVE_Z";
const string LINE_SMA_MAIN  = "7LCEA_SMA_MAIN";
const string LINE_SMA_SELL  = "7LCEA_SMA_SELL_Z";
const string LINE_SMA_BUY   = "7LCEA_SMA_BUY_Z";
const long   WEEK_SEC       = 604800;
const long   DAY_SEC        = 86400;
const long   MERGE_GAP_SEC  = 12 * 3600;   // ช่องว่าง session สั้นกว่านี้ (เช่นพักรายวัน) ถือว่าตลาดยังเปิด

struct WeekBlock {
   long s;   // วินาทีนับจากวันอาทิตย์ 00:00 (เวลาเซิร์ฟเวอร์)
   long e;
};

// สถานะเฝ้าค่าสุดขั้ว (No new high/low) ของแต่ละฝั่ง — ใช้ร่วมกันทั้ง EA จริงและ Tick Replay
struct WatchState {
   bool   active;
   int    tier;       // ระดับวิกฤตตาม Z ปัจจุบัน (1-3) → กำหนดเวลารอ / Lot / SL
   int    max_tier;   // ระดับลึกสุดระหว่างเฝ้า
   double ext_r;      // ค่าสุดขั้วของ Z_reg ระหว่างเฝ้า
   double ext_s;      // ค่าสุดขั้วของ Z_SMA ระหว่างเฝ้า
   long   last_new;   // เวลา (msc) ที่ทำค่าสุดขั้วใหม่ล่าสุด
   long   started;    // เวลา (msc) ที่เริ่มเฝ้า (Z แตะ T1)
   double start_px;   // ราคาตอนเริ่มเฝ้า
};

// Cool down หลังชน SL ของ T2 / T3 — ใช้ร่วมกันทั้ง EA จริงและ Tick Replay
struct CoolState {
   int      t2;       // ชน SL ของ T2 ติดต่อกัน
   int      t3;       // ชน SL ของ T3 ติดต่อกัน
   datetime until;    // พักถึงเวลานี้
};

// แคชผลรวมของแท่งที่ปิดแล้ว (ใช้ร่วมกันทั้ง EA จริงและ Tick Replay)
struct ZCache {
   bool   ok;
   double ref, sY, sXY, sYY, sD, sDD, last_close;
   double prev_zr, prev_zs;   // Z ตอนปิดแท่งล่าสุด
};

const double NEAR_ZONE = 0.5;   // ระยะ "ใกล้เกณฑ์" สำหรับสีป้าย Z

CTrade    trade;
double    g_pmult        = 1.0;
bool      g_draw         = true;

// --- Z engine (แคชผลรวมของแท่งที่ปิดแล้ว, ค่าเลื่อนจุดอ้างอิง g_ref) ---
datetime  g_zbar_time    = 0;
bool      g_z_ready      = false;
double    g_ref          = 0.0;
bool      g_z_valid      = false;
double    g_z            = 0.0;   // Z สำหรับสีป้าย (ตัวที่ใกล้ 0 กว่าเมื่อทิศเดียวกัน)
double    g_z_reg        = 0.0;   // Regression Z
double    g_center       = 0.0;   // ราคาเส้นกลาง Regression (เส้นถดถอยที่แท่งปัจจุบัน)
double    g_sigma        = 0.0;   // ตัวหาร Regression ที่ใช้จริง
double    g_sma_mean     = 0.0;   // ราคา SMA20 (รวมแท่งปัจจุบัน)
double    g_sma_sd       = 0.0;   // StdDev20
bool      g_sigma_floor  = false; // ตัวหารถูกยกขึ้นเป็นพื้นขั้นต่ำ
double    g_z_sma        = 0.0;   // Z แบบ SMA เดิม (แสดงเทียบ)
double    g_prev_close_zr = 0.0;  // Regression Z ของแท่งที่เพิ่งปิด
double    g_prev_close_zs = 0.0;  // SMA Z ของแท่งที่เพิ่งปิด

// --- ช่วงแกว่งแท่งปัจจุบัน / ข่าว ---
double    g_bar0_hi      = 0.0;
double    g_bar0_lo      = 0.0;
datetime  g_news_times[];             // ข่าว High (เรียงเวลา) ตั้งแต่ช่วง Tick Replay ถึง +24 ชม.
string    g_news_names[];
datetime  g_news_loaded  = 0;
bool      g_news_ok      = false;   // โหลดปฏิทินข่าวสำเร็จแล้วอย่างน้อย 1 ครั้ง

// --- เฝ้าค่าสุดขั้ว / Cool down (EA จริง) ---
WatchState g_wsell;
WatchState g_wbuy;
CoolState  g_cool;
bool       g_bar_changed    = false;   // ขึ้นแท่งใหม่ (TF ของ Z) → ล้างการเฝ้า
long       g_last_tick_msc  = 0;
datetime   g_next_try       = 0;
string     g_last_status    = "เริ่มทำงาน";
ulong      g_activated[];              // ไม้ที่ระบบไล่จี้เริ่มทำงานแล้ว
ulong      g_peak_tk[];                // กำไรสูงสุดของแต่ละไม้ (ราคา) สำหรับกฎคืนกำไร
double     g_peak_px[];
datetime   g_gb_retry       = 0;       // ปิดตามกฎคืนกำไรไม่สำเร็จ → ลองใหม่หลังเวลานี้

// --- Session ---
WeekBlock g_blocks[];
int       g_block_count  = 0;
bool      g_always_open  = false;
bool      g_session_ok   = false;
datetime  g_blk_open     = 0;
datetime  g_blk_close    = 0;
bool      g_blk_valid    = false;

// --- UI ---
datetime  g_last_trail   = 0;
string    g_last_comment = "";
double    g_line_main    = 0.0;
double    g_line_sell    = 0.0;
double    g_line_buy     = 0.0;
double    g_line_sma_main = 0.0;
double    g_line_sma_sell = 0.0;
double    g_line_sma_buy  = 0.0;
string    g_live_z_text  = "";
int       g_live_z_y     = -1;

// --- เส้น 7 เส้น (TF ของกราฟ, เรียงเก่า→ใหม่) ---
double    g_lc[];                 // ราคาปิด (แท่งสุดท้าย = แท่งปัจจุบัน)
datetime  g_lt[];                 // เวลาแท่ง
double    g_lv[][7];              // ค่าเส้นทั้ง 7 ต่อแท่ง
int       g_lines_total  = 0;
int       g_lines_warm   = 0;     // ดัชนีแรกที่เส้น 2-7 คำนวณได้ครบ
datetime  g_lines_bar    = 0;     // เวลาแท่งปัจจุบันตอนคำนวณชุดล่าสุด
string    g_lines_status = "ยังไม่ได้วาด";
double    g_alma_w[];
double    g_alma_wsum    = 0.0;

//====================================================================
// 🧰 HELPERS
//====================================================================
double PtsToPrice(double pts) { return pts * g_pmult * _Point; }
double PriceToPts(double px)  { return px / (g_pmult * _Point); }
double ND(double price)       { return NormalizeDouble(price, _Digits); }

datetime ServerNow() {
   datetime t = TimeTradeServer();
   if(t <= 0) t = TimeCurrent();
   return t;
}

datetime CurrentZBarTime() {
   return iTime(_Symbol, InpZ_Timeframe, 0);
}

double NormalizeLot(double lot) {
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0.0) step = 0.01;
   lot = MathFloor(lot / step + 1e-9) * step;
   lot = MathMax(vmin, MathMin(vmax, lot));
   int digits = (int)MathMax(0, MathCeil(-MathLog10(step) - 1e-9));
   return NormalizeDouble(lot, digits);
}

string FormatDuration(long sec) {
   if(sec < 0) sec = 0;
   int d = (int)(sec / DAY_SEC);
   int h = (int)((sec % DAY_SEC) / 3600);
   int m = (int)((sec % 3600) / 60);
   int s = (int)(sec % 60);
   if(d > 0) return StringFormat("%dวัน %dชม. %02dน.", d, h, m);
   if(h > 0) return StringFormat("%dชม. %02dน.", h, m);
   return StringFormat("%dน. %02dว.", m, s);
}

bool IsOurPosition() {
   return (PositionGetInteger(POSITION_MAGIC) == InpMagic &&
           PositionGetString(POSITION_SYMBOL) == _Symbol);
}

void CountPositions(int &buys, int &sells) {
   buys = 0; sells = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsOurPosition()) continue;
      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) buys++;
      else sells++;
   }
}

//--- รายการไม้ที่ระบบไล่จี้เริ่มทำงานแล้ว ---
bool IsActivated(ulong ticket) {
   for(int i = ArraySize(g_activated) - 1; i >= 0; i--)
      if(g_activated[i] == ticket) return true;
   return false;
}

void MarkActivated(ulong ticket) {
   if(IsActivated(ticket)) return;
   int n = ArraySize(g_activated);
   ArrayResize(g_activated, n + 1);
   g_activated[n] = ticket;
}

void PruneActivated() {
   int n = ArraySize(g_activated), w = 0;
   for(int i = 0; i < n; i++)
      if(PositionSelectByTicket(g_activated[i])) g_activated[w++] = g_activated[i];
   if(w != n) ArrayResize(g_activated, w);
}

//--- กำไรสูงสุดของแต่ละไม้ (ราคา) สำหรับกฎคืนกำไร ---
double PeakOf(ulong ticket) {
   for(int i = ArraySize(g_peak_tk) - 1; i >= 0; i--)
      if(g_peak_tk[i] == ticket) return g_peak_px[i];
   return 0.0;
}

double PeakUpdate(ulong ticket, double prof) {
   int n = ArraySize(g_peak_tk);
   for(int i = 0; i < n; i++)
      if(g_peak_tk[i] == ticket) { if(prof > g_peak_px[i]) g_peak_px[i] = prof; return g_peak_px[i]; }
   ArrayResize(g_peak_tk, n + 1);
   ArrayResize(g_peak_px, n + 1);
   g_peak_tk[n] = ticket;
   g_peak_px[n] = MathMax(0.0, prof);
   return g_peak_px[n];
}

void PrunePeaks() {
   int n = ArraySize(g_peak_tk), w = 0;
   for(int i = 0; i < n; i++)
      if(PositionSelectByTicket(g_peak_tk[i])) { g_peak_tk[w] = g_peak_tk[i]; g_peak_px[w] = g_peak_px[i]; w++; }
   if(w != n) { ArrayResize(g_peak_tk, w); ArrayResize(g_peak_px, w); }
}

// กฎคืนกำไร (ใช้ร่วมกัน): กำไรสูงสุดยังไม่ถึงจุดเริ่มไล่จี้ แต่ถึง InpGivebackMinPeak_Pts
//   และกำไรตอนนี้คืนเกิน InpGiveback_Pct% จากจุดสูงสุด → ตัดจบ (peak / prof เป็นระยะราคา)
bool GivebackHit(double peak, double prof) {
   if(InpGiveback_Pct <= 0.0 || peak <= 0.0) return false;
   if(peak < PtsToPrice(InpGivebackMinPeak_Pts) || peak >= PtsToPrice(InpTrailStart_Pts)) return false;
   return prof <= peak * (1.0 - InpGiveback_Pct / 100.0);
}

//====================================================================
// 🧮 Z สำหรับสีป้าย: ตัวที่ใกล้ 0 กว่าเมื่อทิศเดียวกัน (T1 / T2 ต้องถึงเกณฑ์ทั้งคู่)
//====================================================================
double EffectiveZ(double zr, double zs) {
   if(zr > 0.0 && zs > 0.0) return MathMin(zr, zs);
   if(zr < 0.0 && zs < 0.0) return MathMax(zr, zs);
   return 0.0;
}

//====================================================================
// 📐 Z-SCORE ENGINE (Regression Z)
//   x = 0..n-1 (แท่งปัจจุบัน x = n-1), y = ราคาปิด − g_ref
//   เส้นถดถอย y = a + b·x, ส่วนเบี่ยงเบน SSR = Σy² − aΣy − bΣxy
//   Z_reg = (y_ปัจจุบัน − เส้นถดถอยที่ x=n-1) / max(σ_residual, FloorMult × σ_ส่วนต่างต่อแท่ง)
//   แท่งปิดถูกแคชเป็น Σy, Σxy, Σy², Σd, Σd² → ต่อ Tick คำนวณ O(1)
//====================================================================
bool ComputeZ(double sy, double sxy, double syy, double y_last, double sd, double sdd,
              double &z_reg, double &z_sma, double &fit, double &sigma, bool &floored,
              double &mean, double &sd_sma) {
   double n   = (double)InpZ_Period;
   double sx  = n * (n - 1.0) / 2.0;
   double sxx = (n - 1.0) * n * (2.0 * n - 1.0) / 6.0;

   mean          = sy / n;
   double var_sm = syy / n - mean * mean;
   if(var_sm <= 0.0) return false;
   sd_sma        = MathSqrt(var_sm);

   double denom = n * sxx - sx * sx;
   double b     = (n * sxy - sx * sy) / denom;
   double a     = (sy - b * sx) / n;
   fit          = a + b * (n - 1.0);

   double ssr = syy - a * sy - b * sxy;
   if(ssr < 0.0) ssr = 0.0;
   double sd_res = MathSqrt(ssr / n);

   // StdDev ของส่วนต่างราคาต่อแท่ง (n-1 ค่า) — สเกลความผันผวนที่ไม่พองตามความชันเทรนด์
   double m      = n - 1.0;
   double md     = sd / m;
   double var_d  = sdd / m - md * md;
   double sd_min = (var_d > 0.0) ? MathSqrt(var_d) * InpSigmaFloorMult : 0.0;

   floored = (sd_res < sd_min);
   sigma   = floored ? sd_min : sd_res;
   if(sigma <= 0.0) return false;

   z_reg = (y_last - fit)  / sigma;
   z_sma = (y_last - mean) / sd_sma;
   return true;
}

// สร้างแคชจากราคาปิด n แท่ง (c[0..n-1] เก่า→ใหม่, c[n-1] = แท่งที่เพิ่งปิด)
bool BuildZCache(const double &c[], ZCache &zc) {
   int n = InpZ_Period;
   zc.ok  = false;
   zc.ref = c[n - 1];

   // 1. Z ตอนปิดแท่งล่าสุด (n แท่งปิด, แท่งล่าสุดอยู่ x = n-1)
   double sy = 0.0, sxy = 0.0, syy = 0.0, sd = 0.0, sdd = 0.0;
   for(int k = 0; k < n; k++) {
      double y = c[k] - zc.ref;
      sy += y; sxy += k * y; syy += y * y;
      if(k > 0) { double d = c[k] - c[k - 1]; sd += d; sdd += d * d; }
   }
   double zr, zs, fit, sig, mn, ssd;
   bool   fl;
   if(ComputeZ(sy, sxy, syy, 0.0, sd, sdd, zr, zs, fit, sig, fl, mn, ssd)) { zc.prev_zr = zr; zc.prev_zs = zs; }
   else                                                                     { zc.prev_zr = 0.0; zc.prev_zs = 0.0; }

   // 2. แคชแท่งปิด n-1 แท่งล่าสุดสำหรับคำนวณสด (x = 0..n-2) + ส่วนต่างระหว่างแท่งปิด (n-2 ค่า)
   zc.sY = 0.0; zc.sXY = 0.0; zc.sYY = 0.0; zc.sD = 0.0; zc.sDD = 0.0;
   for(int k = 1; k < n; k++) {
      double y = c[k] - zc.ref;
      int    x = k - 1;
      zc.sY += y; zc.sXY += x * y; zc.sYY += y * y;
      if(k > 1) { double d = c[k] - c[k - 1]; zc.sD += d; zc.sDD += d * d; }
   }
   zc.last_close = c[n - 1];
   zc.ok = true;
   return true;
}

// Z ทั้งสองที่ราคา price โดยใช้แคช (fit / mn เป็นค่าสัมพัทธ์กับ zc.ref)
bool ZAtPrice(const ZCache &zc, double price, double &zr, double &zs,
              double &fit, double &sig, bool &fl, double &mn, double &ssd) {
   if(!zc.ok) return false;
   double n  = (double)InpZ_Period;
   double y  = price - zc.ref;
   double d0 = price - zc.last_close;
   return ComputeZ(zc.sY + y, zc.sXY + (n - 1.0) * y, zc.sYY + y * y, y,
                   zc.sD + d0, zc.sDD + d0 * d0, zr, zs, fit, sig, fl, mn, ssd);
}

ZCache g_zc;

bool RefreshClosedBars() {
   datetime t0 = CurrentZBarTime();
   if(t0 == 0) return false;
   if(g_z_ready && t0 == g_zbar_time) return true;

   int    n = InpZ_Period;
   double c[];
   if(CopyClose(_Symbol, InpZ_Timeframe, 1, n, c) != n) {
      g_z_ready = false;
      return false;
   }
   BuildZCache(c, g_zc);
   g_ref           = g_zc.ref;
   g_prev_close_zr = g_zc.prev_zr;
   g_prev_close_zs = g_zc.prev_zs;
   if(g_zbar_time != 0) g_bar_changed = true;

   // ช่วงแกว่งของแท่งปัจจุบัน
   g_bar0_hi = iHigh(_Symbol, InpZ_Timeframe, 0);
   g_bar0_lo = iLow (_Symbol, InpZ_Timeframe, 0);

   g_zbar_time = t0;
   g_z_ready   = true;
   return true;
}

bool UpdateZ(double bid) {
   g_z_valid = false;
   if(!RefreshClosedBars()) return false;

   if(bid > g_bar0_hi)                    g_bar0_hi = bid;
   if(g_bar0_lo <= 0.0 || bid < g_bar0_lo) g_bar0_lo = bid;

   double zr, zs, fit, sig, mn, ssd;
   bool   fl;
   if(!ZAtPrice(g_zc, bid, zr, zs, fit, sig, fl, mn, ssd)) return false;

   g_z_reg       = zr;
   g_z_sma       = zs;
   g_z           = EffectiveZ(zr, zs);
   g_sma_mean    = g_ref + mn;
   g_sma_sd      = ssd;
   g_center      = g_ref + fit;
   g_sigma       = sig;
   g_sigma_floor = fl;
   g_z_valid     = true;
   return true;
}

//====================================================================
// 📰 ปฏิทินข่าว (โหลดทุก 10 นาที, ใช้เวลาเซิร์ฟเวอร์)
//====================================================================
bool NewsEnabled() {
   return !MQLInfoInteger(MQL_TESTER);
}

bool NewsFilterOn() {
   return InpNewsFilter && InpNewsBlock_Min > 0 && NewsEnabled();
}

// โหลดข่าว High ของสกุลที่เลือก ตั้งแต่ต้นช่วง Tick Replay ถึง +24 ชม. (ทุก 10 นาที) — ใช้กรองการเข้าไม้ + แสดงบน Dashboard
void RefreshNews(datetime now) {
   if(!NewsEnabled() || (!InpNewsFilter && !InpShowNewsHistory)) return;
   if(g_news_loaded != 0 && now - g_news_loaded < 600) return;
   g_news_loaded = now;

   datetime from = now - (datetime)((InpReplayDays + 2) * DAY_SEC);
   MqlCalendarValue vals[];
   if(!CalendarValueHistory(vals, from, now + (datetime)DAY_SEC, NULL, InpNewsCurrency)) {
      PrintFormat("⚠️ โหลดปฏิทินข่าวไม่สำเร็จ (error %d) — ลองใหม่ใน 10 วินาที", GetLastError());
      g_news_loaded = now - 590;
      return;
   }
   g_news_ok = true;
   ArrayResize(g_news_times, 0);
   ArrayResize(g_news_names, 0);
   for(int i = 0; i < ArraySize(vals); i++) {
      MqlCalendarEvent ev;
      if(!CalendarEventById(vals[i].event_id, ev)) continue;
      if(ev.importance != CALENDAR_IMPORTANCE_HIGH) continue;
      // แทรกแบบเรียงเวลา (ใช้ค้นหาแบบแบ่งครึ่งใน NewsNear)
      int n = ArraySize(g_news_times);
      ArrayResize(g_news_times, n + 1);
      ArrayResize(g_news_names, n + 1);
      int k = n;
      while(k > 0 && g_news_times[k - 1] > vals[i].time) {
         g_news_times[k] = g_news_times[k - 1];
         g_news_names[k] = g_news_names[k - 1];
         k--;
      }
      g_news_times[k] = vals[i].time;
      g_news_names[k] = ev.name;
   }
}

// ข่าวที่อยู่ในช่วง ±InpNewsBlock_Min นาทีจากเวลา t → index ใน g_news_times (−1 = ไม่มี / ปิดตัวกรอง)
int NewsNear(datetime t) {
   if(!NewsFilterOn()) return -1;
   int  n  = ArraySize(g_news_times);
   long w  = (long)InpNewsBlock_Min * 60;
   int  lo = 0, hi = n;
   while(lo < hi) {   // ข่าวแรกที่เวลา ≥ t − w
      int mid = (lo + hi) / 2;
      if((long)g_news_times[mid] < (long)t - w) lo = mid + 1;
      else hi = mid;
   }
   if(lo < n && (long)g_news_times[lo] <= (long)t + w) return lo;
   return -1;
}

// แท่ง (TF ของ Z) ที่เริ่มเวลา bar_t มีข่าวออกในแท่งไหม
bool IsNewsBar(datetime bar_t, string &name) {
   if(!NewsEnabled() || bar_t == 0) return false;
   datetime bar_end = bar_t + (datetime)PeriodSeconds(InpZ_Timeframe);
   for(int i = 0; i < ArraySize(g_news_times); i++)
      if(g_news_times[i] >= bar_t && g_news_times[i] < bar_end) { name = g_news_names[i]; return true; }
   return false;
}

string NextNewsText(datetime now) {
   if(!InpShowNewsHistory && !InpNewsFilter) return "";
   if(!NewsEnabled()) return "📰 ปฏิทินข่าวใช้ไม่ได้ใน Tester (ไม่กรองข่าว)";
   int k = NewsNear(now);
   if(k >= 0) return StringFormat("🚫 งดเข้าไม้ช่วงข่าว: %s %s", TimeToString(g_news_times[k], TIME_MINUTES), g_news_names[k]);
   string name;
   if(IsNewsBar(CurrentZBarTime(), name)) return "📰 แท่งข่าว: " + name;
   datetime best = 0;
   string   best_name = "";
   for(int i = 0; i < ArraySize(g_news_times); i++)
      if(g_news_times[i] > now && (best == 0 || g_news_times[i] < best)) { best = g_news_times[i]; best_name = g_news_names[i]; }
   if(best == 0) return "📰 ไม่มีข่าว High ใน 24 ชม.";
   return StringFormat("📰 ข่าวถัดไป %s (อีก %s)", best_name, FormatDuration((long)(best - now)));
}

//====================================================================
// 🎯 SIGNAL: เฝ้าค่าสุดขั้ว No new high/low + Cool down (ใช้ร่วมกันทั้ง EA จริงและ Tick Replay)
//====================================================================
// เกณฑ์ Z ของแต่ละระดับ (ขนาด, ใช้เหมือนกันทั้ง SELL +Z / BUY −Z)
double TierZ(int tier) {
   return (tier >= 3) ? InpT3_Z : ((tier == 2) ? InpT2_Z : InpT1_Z);
}

// ระดับวิกฤต (ตรวจ T3 → T2 → T1): 3 = Z ตัวใดตัวหนึ่ง > T3, 2 = ทั้งคู่ > T2, 1 = ทั้งคู่ > T1, 0 = ไม่ถึง
int TierOf(int dir, double zr, double zs) {
   double a_r = (dir == -1) ? zr : -zr;
   double a_s = (dir == -1) ? zs : -zs;
   if(a_r > InpT3_Z || a_s > InpT3_Z) return 3;
   if(a_r > InpT2_Z && a_s > InpT2_Z) return 2;
   if(a_r > InpT1_Z && a_s > InpT1_Z) return 1;
   return 0;
}

// เวลารอ (ไม่มีค่าสุดขั้วใหม่) ของแต่ละระดับ — T3 ยิงทันที
long TierWaitMs(int tier) {
   if(tier >= 3) return 0;
   return (long)(tier == 2 ? InpT2_Sec : InpT1_Sec) * 1000;
}

// Lot ตามระดับที่ยิง: T1 = InpLot, T2 = +step, T3 = +2·step
double TierLot(int tier) { return NormalizeLot(InpLot + (MathMax(1, tier) - 1) * InpTierLotStep); }

string StageTag(int tier) { return "T" + IntegerToString(tier); }

void WatchReset(WatchState &w) {
   w.active   = false;
   w.tier     = 0;
   w.max_tier = 0;
   w.ext_r    = 0.0;
   w.ext_s    = 0.0;
   w.last_new = 0;
   w.started  = 0;
   w.start_px = 0.0;
}

// อัปเดตการเฝ้า: เริ่มเมื่อถึง T1 ขึ้นไป, Z ตัวใดทำค่าสุดขั้วใหม่ = นับเวลาใหม่,
// ระดับตาม Z ปัจจุบัน (ลึกขึ้น = รอสั้นลง / หลุดเกณฑ์ของระดับ = ลดระดับ นับเวลาจากค่าสุดขั้วล่าสุด),
// ไม่ถึง T1 (Z ตัวใดต่ำกว่า T1 และไม่มีตัวไหนเกิน T3) → ยกเลิก แล้วหาสัญญาณใหม่
void WatchUpdate(WatchState &w, int dir, double zr, double zs, long now_msc, double price) {
   int tier = TierOf(dir, zr, zs);
   if(!w.active) {
      if(tier < 1) return;
      WatchReset(w);
      w.active   = true;
      w.tier     = tier;
      w.max_tier = tier;
      w.ext_r    = zr;
      w.ext_s    = zs;
      w.last_new = now_msc;
      w.started  = now_msc;
      w.start_px = price;
      return;
   }
   if(tier < 1) { WatchReset(w); return; }
   bool nr, ns;
   if(dir == -1) { nr = (zr > w.ext_r + InpNoNewExtEps); ns = (zs > w.ext_s + InpNoNewExtEps); }
   else          { nr = (zr < w.ext_r - InpNoNewExtEps); ns = (zs < w.ext_s - InpNoNewExtEps); }
   if(nr) w.ext_r = zr;
   if(ns) w.ext_s = zs;
   if(nr || ns) w.last_new = now_msc;
   w.tier = tier;
   if(tier > w.max_tier) w.max_tier = tier;
}

long WatchDeadline(const WatchState &w) { return w.last_new + TierWaitMs(w.tier); }
bool WatchReady(const WatchState &w, long now_msc) { return w.active && now_msc >= WatchDeadline(w); }

// อยู่ในช่วงห้ามเปิดไม้ต้นแท่งไหม (เวลาแท่งของ TF ของ Z ตรงกับเวลาเซิร์ฟเวอร์หารลงตัว)
bool InBarStartDelay(datetime t) {
   long per = PeriodSeconds(InpZ_Timeframe);
   if(per <= 0) return false;
   return ((long)t % per) < (long)InpBarStartDelay_Sec;
}

// ห้ามเฝ้า / เปิดไม้ช่วงท้ายแท่ง (InpBarEndBlock_Sec วินาทีก่อนปิดแท่งของ TF ของ Z)
bool InBarEndBlock(datetime t) {
   long per = PeriodSeconds(InpZ_Timeframe);
   if(per <= 0 || InpBarEndBlock_Sec <= 0) return false;
   return ((long)t % per) >= per - (long)InpBarEndBlock_Sec;
}

// ช่วงเวลาที่ห้ามเฝ้า / เปิดไม้ (ไม้ที่ถืออยู่ไม่เกี่ยว): นาทีแรก / ท้ายแท่ง / ข่าว High ± InpNewsBlock_Min
string TimeBlockReason(datetime t) {
   if(InBarStartDelay(t)) return "นาทีแรกของแท่ง";
   if(InBarEndBlock(t))   return "ท้ายแท่ง";
   if(NewsNear(t) >= 0)   return "ช่วงข่าว";
   return "";
}

// ระยะ SL เลยยอดไส้ของแต่ละระดับ (จุด)
double SLBeyondPts(int tier) { return (tier >= 3) ? InpSLBeyondT3_Pts : InpSLBeyond_Pts; }

// SL: เลย High (SELL) / Low (BUY) สูงสุดของแท่ง (TF ของ Z) ณ ตอนเปิดไม้ ออกไปตามระดับ
double SLPrice(int dir, double bar_hi, double bar_lo, int tier) {
   double d = PtsToPrice(SLBeyondPts(tier));
   return (dir == -1) ? bar_hi + d : bar_lo - d;
}

// ตัวกรองตอนยิง (ใช้ร่วมกัน) — เวลาตลาด + เพดานสเปรด
string EntryBlockReason(int ts, double bid, double ask) {
   if(ts != TS_OPEN) return "เวลาตลาด";
   double sp = PriceToPts(ask - bid);
   if(sp > InpMaxSpread_Pts) return StringFormat("สเปรด %.0f > %.0f จุด", sp, InpMaxSpread_Pts);
   return "";
}

bool TradeAllowed() {
   return TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) && MQLInfoInteger(MQL_TRADE_ALLOWED);
}

//--- Cool down: ชน SL (ขาดทุน) ของ T3 InpCoolT3_SL ครั้ง หรือของ T2 InpCoolT2_SL ครั้งติดต่อกัน → พัก InpCooldown_Min นาที ---
//    ไม้ที่ปิดแบบอื่น (ไม่ใช่ SL ขาดทุน) ล้างตัวนับ, SL ของ T1 ไม่นับและไม่ล้าง, เริ่มพักแล้วล้างตัวนับ
void CoolReset(CoolState &c) { c.t2 = 0; c.t3 = 0; c.until = 0; }

// ไม้ระดับ tier ปิด → true = เริ่มพัก
bool CoolOnClose(CoolState &c, int tier, bool sl_loss, datetime t) {
   if(!sl_loss) { c.t2 = 0; c.t3 = 0; return false; }
   bool start = false;
   if(tier >= 3)      { c.t3++; start = (InpCoolT3_SL > 0 && c.t3 >= InpCoolT3_SL); }
   else if(tier == 2) { c.t2++; start = (InpCoolT2_SL > 0 && c.t2 >= InpCoolT2_SL); }
   if(!start) return false;
   c.t2    = 0;
   c.t3    = 0;
   c.until = t + (datetime)(InpCooldown_Min * 60);
   return true;
}

bool CoolActive(const CoolState &c, datetime t) { return t < c.until; }

//====================================================================
// 🕒 SESSION (เวลาเปิด/ปิดตลาดรายสัปดาห์จาก SymbolInfoSessionTrade)
//====================================================================
bool BuildWeekBlocks() {
   WeekBlock raw[];
   int n = 0;
   for(int d = 0; d < 7; d++) {
      for(uint idx = 0; idx < 16; idx++) {
         datetime from = 0, to = 0;
         if(!SymbolInfoSessionTrade(_Symbol, (ENUM_DAY_OF_WEEK)d, idx, from, to)) break;
         long s = (long)d * DAY_SEC + (long)from;
         long e = (long)d * DAY_SEC + (long)to;
         if(e <= s) e += DAY_SEC;   // session ข้ามเที่ยงคืน
         ArrayResize(raw, n + 1);
         raw[n].s = s;
         raw[n].e = e;
         n++;
      }
   }
   g_block_count = 0;
   g_always_open = false;
   if(n == 0) return false;

   // เรียงตามเวลาเริ่ม
   for(int i = 1; i < n; i++) {
      WeekBlock key = raw[i];
      int j = i - 1;
      while(j >= 0 && raw[j].s > key.s) { raw[j + 1] = raw[j]; j--; }
      raw[j + 1] = key;
   }

   // รวม session ที่ต่อกัน / มีช่องว่างสั้น (พักรายวัน) ให้เป็นช่วงเดียว
   ArrayResize(g_blocks, n);
   for(int i = 0; i < n; i++) {
      if(g_block_count > 0 && raw[i].s - g_blocks[g_block_count - 1].e <= MERGE_GAP_SEC) {
         g_blocks[g_block_count - 1].e = MathMax(g_blocks[g_block_count - 1].e, raw[i].e);
      } else {
         g_blocks[g_block_count] = raw[i];
         g_block_count++;
      }
   }

   // รวมช่วงท้ายสัปดาห์กับช่วงต้นสัปดาห์ หากต่อกันข้ามคืนวันเสาร์→อาทิตย์
   if(g_block_count > 1 &&
      (g_blocks[0].s + WEEK_SEC) - g_blocks[g_block_count - 1].e <= MERGE_GAP_SEC) {
      g_blocks[g_block_count - 1].e = g_blocks[0].e + WEEK_SEC;
      for(int i = 1; i < g_block_count; i++) g_blocks[i - 1] = g_blocks[i];
      g_block_count--;
   }
   else if(g_block_count == 1 &&
           (g_blocks[0].s + WEEK_SEC) - g_blocks[0].e <= MERGE_GAP_SEC) {
      g_always_open = true;   // ตลาดเปิดตลอดสัปดาห์
   }
   ArrayResize(g_blocks, g_block_count);
   return (g_block_count > 0);
}

// หาช่วงตลาดเปิด (รายสัปดาห์) ที่ครอบเวลา t — ไม่ใช้แคช
bool LocateBlockAt(datetime t_now, datetime &open_t, datetime &close_t) {
   MqlDateTime dt;
   TimeToStruct(t_now, dt);
   datetime week_start = t_now - (datetime)(dt.day_of_week * DAY_SEC + dt.hour * 3600 + dt.min * 60 + dt.sec);
   long t = (long)(t_now - week_start);

   for(int i = 0; i < g_block_count; i++) {
      long s = g_blocks[i].s, e = g_blocks[i].e;
      if(t >= s && t < e) {
         open_t  = week_start + (datetime)s;
         close_t = week_start + (datetime)e;
         return true;
      }
      if(t + WEEK_SEC >= s && t + WEEK_SEC < e) {   // ช่วงที่เริ่มสัปดาห์ก่อนแล้วลากข้ามมา
         open_t  = week_start + (datetime)(s - WEEK_SEC);
         close_t = week_start + (datetime)(e - WEEK_SEC);
         return true;
      }
   }
   return false;
}

bool LocateBlock(datetime now) {
   if(g_blk_valid && now >= g_blk_open && now < g_blk_close) return true;
   g_blk_valid = LocateBlockAt(now, g_blk_open, g_blk_close);
   return g_blk_valid;
}

int GetTimeStateAt(datetime t) {
   if(!g_session_ok || g_always_open) return TS_OPEN;
   datetime o, c;
   if(!LocateBlockAt(t, o, c)) return TS_CLOSED;
   if(t >= c - (datetime)(InpCloseBeforeClose_Min * 60)) return TS_CLOSING;
   if(t <  o + (datetime)(InpNoTradeAfterOpen_Min * 60)) return TS_WAIT_OPEN;
   return TS_OPEN;
}

// เวลาเริ่มบังคับปิดของช่วงตลาดที่ครอบเวลา t (0 = ไม่มี)
datetime ForceCloseTimeAt(datetime t) {
   if(!g_session_ok || g_always_open) return 0;
   datetime o, c;
   if(!LocateBlockAt(t, o, c)) return 0;
   return c - (datetime)(InpCloseBeforeClose_Min * 60);
}

int GetTimeState(datetime now) {
   if(!g_session_ok || g_always_open) return TS_OPEN;
   if(!LocateBlock(now)) return TS_CLOSED;
   if(now >= g_blk_close - (datetime)(InpCloseBeforeClose_Min * 60)) return TS_CLOSING;
   if(now <  g_blk_open  + (datetime)(InpNoTradeAfterOpen_Min * 60)) return TS_WAIT_OPEN;
   return TS_OPEN;
}

string TimeStateText(int ts, datetime now) {
   if(!g_session_ok)  return "⚠️ ไม่มีข้อมูล Session (ไม่กรองเวลา)";
   if(g_always_open)  return "ตลาดเปิดตลอด (ไม่กรองเวลา)";
   switch(ts) {
      case TS_OPEN:
         return "✅ เทรดได้ | อีก " + FormatDuration((long)(g_blk_close - (datetime)(InpCloseBeforeClose_Min * 60) - now)) + " จะเริ่มบังคับปิด";
      case TS_WAIT_OPEN:
         return "⏳ ห้ามเข้า (ชั่วโมงแรกหลังเปิดสัปดาห์) | อีก " + FormatDuration((long)(g_blk_open + (datetime)(InpNoTradeAfterOpen_Min * 60) - now));
      case TS_CLOSING:
         return "🛑 ช่วงบังคับปิดก่อนตลาดปิด | ตลาดปิดในอีก " + FormatDuration((long)(g_blk_close - now));
   }
   return "💤 ตลาดปิด";
}

//====================================================================
// 💼 ORDER MANAGEMENT
//====================================================================
// เปิด Market สวนกลับ: stage = ระดับวิกฤต (1-3) → Lot ตามระดับ, TP / SL ชุดเดียวกัน
bool OpenMarket(int dir, int stage, double bid, double ask, ulong &ticket) {
   double lot   = TierLot(stage);
   double price = (dir == -1) ? bid : ask;
   double hi    = MathMax(g_bar0_hi, bid);
   double lo    = (g_bar0_lo > 0.0) ? MathMin(g_bar0_lo, bid) : bid;
   double stops = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double sl    = SLPrice(dir, hi, lo, stage);
   if(dir == -1) sl = MathMax(sl, ask + stops + _Point);   // เคารพ Stops Level ของโบรก
   else          sl = MathMin(sl, bid - stops - _Point);
   sl = ND(sl);
   double tp    = ND(dir == -1 ? price - PtsToPrice(InpTP_Pts) : price + PtsToPrice(InpTP_Pts));
   string cmt   = StringFormat("%s %s R%+.1f S%+.1f", InpOrderComment, StageTag(stage), g_z_reg, g_z_sma);
   bool   ok    = (dir == -1) ? trade.Sell(lot, _Symbol, bid, sl, tp, cmt)
                              : trade.Buy (lot, _Symbol, ask, sl, tp, cmt);
   uint rc = trade.ResultRetcode();
   if(ok && (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_PLACED || rc == TRADE_RETCODE_DONE_PARTIAL)) {
      ticket = trade.ResultOrder();
      PrintFormat("✅ เปิด %s %s %.2f lot @ %s | SL %s (%s แท่ง %s ± %.0f จุด, ห่าง %.0f จุด) | Z_reg %+.2f / Z_SMA %+.2f",
                  StageTag(stage), (dir == -1 ? "SELL" : "BUY"), lot, DoubleToString(trade.ResultPrice(), _Digits),
                  DoubleToString(sl, _Digits), (dir == -1 ? "High" : "Low"), DoubleToString(dir == -1 ? hi : lo, _Digits),
                  SLBeyondPts(stage), PriceToPts(MathAbs(sl - price)), g_z_reg, g_z_sma);
      return true;
   }
   PrintFormat("❌ เปิด %s %s ไม่สำเร็จ: %u %s", StageTag(stage), (dir == -1 ? "SELL" : "BUY"), rc, trade.ResultRetcodeDescription());
   return false;
}

int OurPositionsTotal() {
   int b, s;
   CountPositions(b, s);
   return b + s;
}

//--------------------------------------------------------------------
// 🎯 ยิงไม้ + Cool down (EA จริง)
//--------------------------------------------------------------------
// ครบเวลาเฝ้าของระดับ (T1 15 วิ / T2 5 วิ / T3 ทันที) → ตัวกรอง → สวนกลับ (ติดตัวกรอง = ทิ้งสัญญาณ)
void LiveFire(int dir, int ts, double bid, double ask) {
   WatchState w;
   if(dir == -1) w = g_wsell; else w = g_wbuy;
   string   side = (dir == -1) ? "SELL" : "BUY";
   int      tier = w.tier;
   datetime now  = ServerNow();

   string why = EntryBlockReason(ts, bid, ask);
   if(why == "" && !TradeAllowed()) why = "ปิด Algo Trading อยู่";
   if(why != "") {
      g_last_status = StringFormat("เฝ้า %s %s ครบเวลาแล้ว แต่ติด: %s → ทิ้งสัญญาณ", side, StageTag(tier), why);
      if(dir == -1) WatchReset(g_wsell); else WatchReset(g_wbuy);
      return;
   }
   if(now < g_next_try) return;

   ulong ticket = 0;
   if(OpenMarket(dir, tier, bid, ask, ticket)) {
      g_last_status = StringFormat("เปิดสวนกลับ %s %s (Lot %.2f, ลึกสุด T%d) | สุดขั้ว R %+.2f / S %+.2f → ตอนยิง R %+.2f / S %+.2f",
                                   side, StageTag(tier), TierLot(tier), w.max_tier, w.ext_r, w.ext_s, g_z_reg, g_z_sma);
      WatchReset(g_wsell);
      WatchReset(g_wbuy);
   } else {
      g_next_try    = now + 1;   // กันยิงคำสั่งรัว ๆ เมื่อโบรกปฏิเสธ (ยังเฝ้าต่อ)
      g_last_status = side + " ส่งคำสั่งไม่สำเร็จ: " + trade.ResultRetcodeDescription();
   }
}

// เรียกทุก Tick และทุก 1 วินาที — ครั้งละ 1 ไม้: มีไม้ถืออยู่ / ช่วงห้าม (นาทีแรก ท้ายแท่ง ข่าว) / พักอยู่ = ไม่เฝ้า (ไม่เก็บสัญญาณเข้าคิว)
void LiveSignalStep(long now_msc, int ts, double bid, double ask, bool update_watch) {
   if(!g_z_valid) return;
   datetime now_t   = (datetime)(now_msc / 1000);
   bool     busy    = OurPositionsTotal() > 0;
   bool     blocked = (TimeBlockReason(now_t) != "");
   bool     cool    = CoolActive(g_cool, now_t);

   if(busy || blocked || cool || g_bar_changed) {
      WatchReset(g_wsell);
      WatchReset(g_wbuy);
      g_bar_changed = false;
      if(busy || blocked || cool) return;
   }
   if(update_watch) {
      WatchUpdate(g_wsell, -1, g_z_reg, g_z_sma, now_msc, bid);
      WatchUpdate(g_wbuy,   1, g_z_reg, g_z_sma, now_msc, bid);
   }
   if(WatchReady(g_wsell, now_msc))     LiveFire(-1, ts, bid, ask);
   else if(WatchReady(g_wbuy, now_msc)) LiveFire( 1, ts, bid, ask);
}

// ระดับ (T1-T3) จากคอมเมนต์ของดีลเปิด เช่น "7L-CNT T2 R+2.5 S+2.9" (0 = อ่านไม่ได้)
int TierFromComment(string c) {
   for(int t = 3; t >= 1; t--)
      if(StringFind(c, " T" + IntegerToString(t) + " ") >= 0) return t;
   return 0;
}

// ระดับของโพซิชันจากดีลเปิด (เปลี่ยนรายการประวัติที่เลือกเป็นของโพซิชันนี้)
int TierOfPosition(long pos_id) {
   if(!HistorySelectByPosition(pos_id)) return 0;
   for(int i = 0; i < HistoryDealsTotal(); i++) {
      ulong d = HistoryDealGetTicket(i);
      if(d > 0 && HistoryDealGetInteger(d, DEAL_ENTRY) == DEAL_ENTRY_IN) return TierFromComment(HistoryDealGetString(d, DEAL_COMMENT));
   }
   return 0;
}

bool IsOurDeal(ulong deal, long entry) {
   return (HistoryDealGetInteger(deal, DEAL_MAGIC) == InpMagic && HistoryDealGetString(deal, DEAL_SYMBOL) == _Symbol &&
           HistoryDealGetInteger(deal, DEAL_ENTRY) == entry);
}

// ดีลปิดไม้ของ EA (deal ต้องถูกเลือกใน history แล้ว) → โพซิชัน / ชน SL ขาดทุนไหม / เวลา
bool OutDealInfo(ulong deal, long &pos_id, bool &sl_loss, datetime &t) {
   if(!IsOurDeal(deal, DEAL_ENTRY_OUT)) return false;
   double profit = HistoryDealGetDouble(deal, DEAL_PROFIT) + HistoryDealGetDouble(deal, DEAL_SWAP) + HistoryDealGetDouble(deal, DEAL_COMMISSION);
   pos_id  = HistoryDealGetInteger(deal, DEAL_POSITION_ID);
   sl_loss = (HistoryDealGetInteger(deal, DEAL_REASON) == DEAL_REASON_SL && profit < 0.0);
   t       = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
   return true;
}

// ไม้ปิด → นับ SL ของ T2 / T3 / เริ่ม Cool down
void CoolApply(int tier, bool sl_loss, datetime t, bool live) {
   if(CoolOnClose(g_cool, tier, sl_loss, t) && live) {
      g_last_status = StringFormat("❄️ ชน SL ของ T%d → พักถึง %s", tier, TimeToString(g_cool.until, TIME_DATE|TIME_MINUTES));
      PrintFormat("%s", g_last_status);
   }
}

// เริ่ม EA: คืนค่าตัวนับ SL ของ T2 / T3 / เวลาพัก จากประวัติ 7 วันล่าสุด (ระดับอ่านจากคอมเมนต์ของดีลเปิด)
void RestoreCoolFromHistory() {
   CoolReset(g_cool);
   datetime now = ServerNow();
   if(!HistorySelect(now - (datetime)(7 * DAY_SEC), now + 60)) return;
   int  total = HistoryDealsTotal();
   long pos_ids[];
   int  pos_tier[];
   for(int i = 0; i < total; i++) {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0 || !IsOurDeal(d, DEAL_ENTRY_IN)) continue;
      int n = ArraySize(pos_ids);
      ArrayResize(pos_ids, n + 1);
      ArrayResize(pos_tier, n + 1);
      pos_ids[n]  = HistoryDealGetInteger(d, DEAL_POSITION_ID);
      pos_tier[n] = TierFromComment(HistoryDealGetString(d, DEAL_COMMENT));
   }
   for(int i = 0; i < total; i++) {
      ulong    d = HistoryDealGetTicket(i);
      long     pos;
      bool     sl_loss;
      datetime t;
      if(d == 0 || !OutDealInfo(d, pos, sl_loss, t)) continue;
      int tier = 0;
      for(int k = ArraySize(pos_ids) - 1; k >= 0; k--)
         if(pos_ids[k] == pos) { tier = pos_tier[k]; break; }
      CoolApply(tier, sl_loss, t, false);
   }
   if(CoolActive(g_cool, now))
      PrintFormat("❄️ คืนค่า Cool down จากประวัติ: พักถึง %s", TimeToString(g_cool.until, TIME_DATE|TIME_MINUTES));
   else if(g_cool.t2 > 0 || g_cool.t3 > 0)
      PrintFormat("ℹ️ คืนค่าตัวนับจากประวัติ: ชน SL ของ T2 %d / T3 %d ครั้ง", g_cool.t2, g_cool.t3);
}

void CloseAllPositions() {
   WatchReset(g_wsell);
   WatchReset(g_wbuy);
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsOurPosition()) continue;
      if(trade.PositionClose(ticket))
         PrintFormat("🛑 ปิดไม้ #%I64u ก่อนตลาดปิดสัปดาห์", ticket);
      else
         PrintFormat("❌ ปิดไม้ #%I64u ไม่สำเร็จ: %u %s (จะลองใหม่)", ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription());
   }
}

// ขยับโล่ของไม้ที่เลือกไว้ (ขยับทางเดียว + เคารพ Stops/Freeze Level)
void TrailPosition(ulong ticket, bool is_buy, double sl, double tp, double bid, double ask,
                   double dist, double stops, double freeze) {
   double new_sl;
   if(is_buy) {
      new_sl = ND(bid - dist);
      if(sl > 0.0 && new_sl - sl < _Point) return;
      if(bid - new_sl < stops) return;
      if(sl > 0.0 && bid - sl <= freeze) return;
      if(tp > 0.0 && tp - bid <= freeze) return;
   } else {
      new_sl = ND(ask + dist);
      if(sl > 0.0 && sl - new_sl < _Point) return;
      if(new_sl - ask < stops) return;
      if(sl > 0.0 && sl - ask <= freeze) return;
      if(tp > 0.0 && ask - tp <= freeze) return;
   }
   if(!trade.PositionModify(ticket, new_sl, tp))
      PrintFormat("⚠️ ขยับโล่ #%I64u ไม่สำเร็จ: %u %s", ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription());
}

// เรียกทุก 1 วินาที: เปิดระบบไล่จี้ / ตัดจบตามเวลา / ขยับโล่ตามรอบ
void ManagePositions(datetime now) {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= 0.0) return;

   bool trail_cycle = (now - g_last_trail >= InpTrailInterval_Sec);
   if(trail_cycle) g_last_trail = now;

   double start  = PtsToPrice(InpTrailStart_Pts);
   double dist   = PtsToPrice(InpTrailDist_Pts);
   double stops  = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL)  * _Point;
   double freeze = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * _Point;

   PruneActivated();
   PrunePeaks();

   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsOurPosition()) continue;

      bool     is_buy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double   open   = PositionGetDouble(POSITION_PRICE_OPEN);
      double   sl     = PositionGetDouble(POSITION_SL);
      double   tp     = PositionGetDouble(POSITION_TP);
      datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
      double   prof   = is_buy ? (bid - open) : (open - ask);

      // ไม้ที่ SL ล็อกกำไรแล้ว (เช่นหลังรีสตาร์ท EA) ถือว่าระบบไล่จี้ทำงานแล้ว
      bool locked = (sl > 0.0) && (is_buy ? (sl > open) : (sl < open));
      if(locked) MarkActivated(ticket);

      if(!IsActivated(ticket)) {
         if(PeakUpdate(ticket, prof) >= start) {
            // กำไร (สูงสุดตั้งแต่เปิด) ถึงจุดเริ่มไล่จี้ → เปิดระบบไล่จี้ทันที (ไม่รอรอบ 5 วินาที)
            MarkActivated(ticket);
            PrintFormat("🔥 #%I64u เริ่มไล่จี้ (กำไร %.0f จุด หลังเปิด %d วินาที)", ticket, PriceToPts(prof), (int)(now - opened));
            TrailPosition(ticket, is_buy, sl, tp, bid, ask, dist, stops, freeze);
         }
         else if(InpQuickWindow_Sec > 0 && now - opened >= InpQuickWindow_Sec) {
            // ครบเวลาแล้วไม่ดีดกลับ → ตัดจบ
            if(trade.PositionClose(ticket)) {
               g_last_status = StringFormat("ตัดจบ #%I64u (ไม่ดีดกลับใน %d วินาที, %+.0f จุด)",
                                            ticket, InpQuickWindow_Sec, PriceToPts(prof));
               PrintFormat("⏱️ %s", g_last_status);
            } else {
               PrintFormat("❌ ตัดจบ #%I64u ไม่สำเร็จ: %u %s (จะลองใหม่)", ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription());
            }
         }
         continue;
      }

      if(trail_cycle) TrailPosition(ticket, is_buy, sl, tp, bid, ask, dist, stops, freeze);
   }
}

// ทุก Tick: อัปเดตกำไรสูงสุดของไม้ + กฎคืนกำไร (ยังไม่ถึงโล่ และกำไรคืนเกิน InpGiveback_Pct% จากจุดสูงสุด → ตัดจบ)
void GivebackStep(double bid, double ask) {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsOurPosition()) continue;
      bool   is_buy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double open   = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl     = PositionGetDouble(POSITION_SL);
      double prof   = is_buy ? (bid - open) : (open - ask);
      double peak   = PeakUpdate(ticket, prof);
      bool   locked = (sl > 0.0) && (is_buy ? (sl > open) : (sl < open));
      if(locked || IsActivated(ticket) || !GivebackHit(peak, prof)) continue;
      if(ServerNow() < g_gb_retry) continue;
      if(trade.PositionClose(ticket)) {
         g_last_status = StringFormat("ตัดจบ #%I64u (คืนกำไร: สูงสุด %.0f → เหลือ %.0f จุด, คืนเกิน %.0f%%)",
                                      ticket, PriceToPts(peak), PriceToPts(prof), InpGiveback_Pct);
         PrintFormat("↩️ %s", g_last_status);
      } else {
         g_gb_retry = ServerNow() + 1;
         PrintFormat("❌ ตัดจบ (คืนกำไร) #%I64u ไม่สำเร็จ: %u %s (จะลองใหม่)", ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription());
      }
   }
}

//====================================================================
// 📈 7 LINES ENGINE (ย้ายมาจาก Indicator v8.82 — คำนวณบน TF ของกราฟ)
//====================================================================
color                 g_line_clr[7];   // ตั้งจาก Input ใน OnInit
const int             LINE_WIDTH[7] = {3, 1, 1, 2, 2, 1, 1};
const ENUM_LINE_STYLE LINE_STYLE[7] = {STYLE_SOLID, STYLE_SOLID, STYLE_SOLID, STYLE_SOLID, STYLE_SOLID, STYLE_DOT, STYLE_DOT};
const string          LINE_LABEL[7] = {"Main (SMA)", "L1 (EMA)", "L2 (LWMA)", "L3 (HMA)", "L4 (LSMA)", "L5 (ALMA)", "L6 (Kinematic)"};

void InitALMAWeights(int period) {
   ArrayResize(g_alma_w, period);
   g_alma_wsum = 0.0;
   double m = 0.85 * (period - 1);
   double s = period / 6.0;
   for(int k = 0; k < period; k++) {
      double x = (period - 1 - k);
      double w = MathExp(-MathPow(x - m, 2) / (2.0 * s * s));
      g_alma_w[k]  = w;
      g_alma_wsum += w;
   }
}

double LnSMA(const double &p[], int i, int period) {
   double sum = 0.0;
   for(int k = 0; k < period; k++) sum += p[i - k];
   return sum / period;
}

double LnWMA(const double &p[], int i, int period) {
   double sum = 0.0, wsum = 0.0;
   for(int k = 0; k < period; k++) {
      double w = (double)(period - k);
      sum += p[i - k] * w; wsum += w;
   }
   return (wsum > 0.0) ? sum / wsum : p[i];
}

double LnHMA(const double &p[], int i, int period) {
   int half_p = (int)MathMax(1, MathFloor(period / 2.0));
   int sqrt_p = (int)MathMax(1, MathFloor(MathSqrt(period)));
   double sum = 0.0, wsum = 0.0;
   for(int k = 0; k < sqrt_p; k++) {
      double diff = 2.0 * LnWMA(p, i - k, half_p) - LnWMA(p, i - k, period);
      double w    = (double)(sqrt_p - k);
      sum += diff * w; wsum += w;
   }
   return (wsum > 0.0) ? sum / wsum : p[i];
}

double LnLSMA(const double &p[], int i, int period) {
   double sx = 0.0, sy = 0.0, sxy = 0.0, sx2 = 0.0;
   for(int k = 0; k < period; k++) {
      double x = (double)(period - k), y = p[i - k];
      sx += x; sy += y; sxy += x * y; sx2 += x * x;
   }
   double denom = period * sx2 - sx * sx;
   if(denom == 0.0) return p[i];
   double m = (period * sxy - sx * sy) / denom;
   double b = (sy - m * sx) / period;
   return m * period + b;
}

double LnALMA(const double &p[], int i, int period) {
   if(g_alma_wsum <= 0.0) return p[i];
   double sum = 0.0;
   for(int k = 0; k < period; k++) sum += p[i - k] * g_alma_w[k];
   return sum / g_alma_wsum;
}

double LnKinematic(const double &p[], int i) {
   double p0 = (p[i]     + p[i - 1] + p[i - 2]) / 3.0;
   double p1 = (p[i - 1] + p[i - 2] + p[i - 3]) / 3.0;
   double p2 = (p[i - 2] + p[i - 3] + p[i - 4]) / 3.0;
   double vel = p0 - p1;
   return p0 + vel + (vel - (p1 - p2));
}

void ComputeLinesAt(int i) {
   double alpha = 2.0 / (InpFastPeriod + 1.0);
   g_lv[i][1] = (i == 0) ? g_lc[0] : g_lc[i] * alpha + g_lv[i - 1][1] * (1.0 - alpha);   // EMA ต่อเนื่องจากต้นหน้าต่าง
   if(i < g_lines_warm) return;
   g_lv[i][0] = LnSMA(g_lc, i, InpZ_Period);
   g_lv[i][2] = LnWMA(g_lc, i, InpFastPeriod);
   g_lv[i][3] = LnHMA(g_lc, i, InpFastPeriod);
   g_lv[i][4] = LnLSMA(g_lc, i, InpFastPeriod);
   g_lv[i][5] = LnALMA(g_lc, i, InpFastPeriod);
   g_lv[i][6] = LnKinematic(g_lc, i);
}

int g_lines_fail = 0;
int g_lines_err  = 0;

void SetLinesStatus(string st) {
   if(st == g_lines_status) return;
   g_lines_status = st;
   Print("📈 เส้น 7 เส้น: ", st);
}

datetime g_seg_times[];   // เวลาแท่งปลายของช่วงเส้นที่วาดอยู่ (เก่า→ใหม่)

string SegName(int L, datetime t) {
   return OBJ_PREFIX + "L" + IntegerToString(L) + "_" + IntegerToString((long)t);
}

// ช่วงเส้นของเส้น L ที่จบที่แท่ง i1 (ตั้งชื่อตามเวลาแท่ง → ไม่ต้องขยับทั้งชุดเมื่อขึ้นแท่งใหม่)
void SetLineSegment(int L, int i1) {
   if(L == 0 ? !InpShowLineMain : !InpShowLineFast) return;
   int i0 = i1 - 1;
   string name = SegName(L, g_lt[i1]);
   if(ObjectFind(0, name) < 0) {
      if(!ObjectCreate(0, name, OBJ_TREND, 0, g_lt[i0], g_lv[i0][L], g_lt[i1], g_lv[i1][L])) {
         g_lines_fail++;
         g_lines_err = GetLastError();
         return;
      }
      ObjectSetInteger(0, name, OBJPROP_COLOR, g_line_clr[L]);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, LINE_WIDTH[L]);
      ObjectSetInteger(0, name, OBJPROP_STYLE, LINE_STYLE[L]);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, name, OBJPROP_RAY_LEFT, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);   // วาดทับแท่งเทียนเหมือนเส้น Indicator
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetString(0,  name, OBJPROP_TOOLTIP, LINE_LABEL[L]);
      return;
   }
   ObjectMove(0, name, 0, g_lt[i0], g_lv[i0][L]);
   ObjectMove(0, name, 1, g_lt[i1], g_lv[i1][L]);
}

void SetBarSegments(int i1) {
   for(int L = 0; L < 7; L++) SetLineSegment(L, i1);
   int n = ArraySize(g_seg_times);
   if(n == 0 || g_seg_times[n - 1] < g_lt[i1]) {
      ArrayResize(g_seg_times, n + 1);
      g_seg_times[n] = g_lt[i1];
   }
}

// ลบช่วงเส้นที่หลุดหน้าต่าง InpLinesBars
void PruneSegments(datetime oldest_end) {
   int n = ArraySize(g_seg_times), w = 0;
   for(int i = 0; i < n; i++) {
      if(g_seg_times[i] < oldest_end) {
         for(int L = 0; L < 7; L++) ObjectDelete(0, SegName(L, g_seg_times[i]));
         continue;
      }
      g_seg_times[w++] = g_seg_times[i];
   }
   if(w != n) ArrayResize(g_seg_times, w);
}

// คำนวณค่าเส้นใหม่ทั้งหน้าต่าง (เบา) แต่แตะ object เฉพาะช่วงที่เปลี่ยน:
//  ครั้งแรก = วาดทั้งหน้าต่าง, ขึ้นแท่งใหม่ = ช่วงของแท่งที่เพิ่งปิด + แท่งใหม่ แล้วลบช่วงที่เก่าเกิน
bool RebuildLines() {
   int sqrt_p   = (int)MathMax(1, MathFloor(MathSqrt(InpFastPeriod)));
   g_lines_warm = MathMax(InpZ_Period, InpFastPeriod + sqrt_p) + 5;
   int total    = InpLinesBars + g_lines_warm + 100;   // +100 แท่งให้ EMA นิ่งก่อนเริ่มวาด

   int got_c = CopyClose(_Symbol, PERIOD_CURRENT, 0, total, g_lc);
   int got_t = CopyTime (_Symbol, PERIOD_CURRENT, 0, total, g_lt);
   if(got_c != total || got_t != total) {
      SetLinesStatus(StringFormat("⏳ รอประวัติราคา (ได้ %d/%d แท่ง, error %d)", MathMin(got_c, got_t), total, GetLastError()));
      g_lines_total = 0;
      return false;
   }
   ArrayResize(g_lv, total);
   bool first = (g_lines_total == 0 || ArraySize(g_seg_times) == 0);
   datetime prev_bar = g_lines_bar;
   g_lines_total = total;

   for(int i = 0; i < total; i++) ComputeLinesAt(i);
   g_lines_fail = 0;

   int oldest_i1 = total - InpLinesBars + 1;
   for(int i1 = oldest_i1; i1 < total; i1++) {
      if(!first && g_lt[i1] < prev_bar) continue;   // ช่วงเก่าวาดไว้แล้ว ไม่ต้องแตะ
      SetBarSegments(i1);
   }
   PruneSegments(g_lt[oldest_i1]);

   g_lines_bar = g_lt[total - 1];
   if(g_lines_fail > 0)
      SetLinesStatus(StringFormat("⚠️ สร้างเส้นไม่สำเร็จ %d ช่วง (error %d)", g_lines_fail, g_lines_err));
   else
      SetLinesStatus(StringFormat("✅ วาดแล้ว %d แท่ง (%s)", InpLinesBars, EnumToString(Period())));
   ChartRedraw(0);
   return true;
}

// ระหว่างแท่ง: อัปเดตเฉพาะค่าแท่งปัจจุบันและช่วงเส้นสุดท้าย
void UpdateLinesLive() {
   if(!g_draw || !InpShow7Lines) return;
   datetime t0 = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(t0 == 0) return;
   if(g_lines_total == 0 || t0 != g_lines_bar) { RebuildLines(); return; }

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int    i   = g_lines_total - 1;
   if(bid <= 0.0 || bid == g_lc[i]) return;
   g_lc[i] = bid;
   ComputeLinesAt(i);
   for(int L = 0; L < 7; L++) SetLineSegment(L, i);
}

//====================================================================
// 🏷️ ป้ายค่า Z บนแท่งที่ถึงเกณฑ์ (TF ของ Z)
//   Z ของแท่ง j ที่ราคา P = Regression Z จากราคาปิด n−1 แท่งก่อนหน้า + P เป็นจุดปัจจุบัน
//   (ตรงกับ Z สดที่ EA เห็นตอนราคาไปถึง P) → SELL ใช้ High, BUY ใช้ Low
//====================================================================
string   g_zl_names[];
datetime g_zl_times[];
datetime g_barz_bar = 0;   // แท่งปัจจุบัน (TF ของ Z) ตอนอัปเดตล่าสุด

bool ZForBarPrice(const double &c[], int j, double price, double &z_reg, double &z_sma) {
   int n = InpZ_Period;
   if(j < n - 1) return false;
   double ref = c[j - 1];
   double sy = 0.0, sxy = 0.0, syy = 0.0, sd = 0.0, sdd = 0.0;
   for(int k = 0; k < n - 1; k++) {
      int    idx = j - (n - 1) + k;
      double y   = c[idx] - ref;
      sy += y; sxy += k * y; syy += y * y;
      if(k > 0) { double d = c[idx] - c[idx - 1]; sd += d; sdd += d * d; }
   }
   double y = price - ref;
   sy += y; sxy += (n - 1) * y; syy += y * y;
   double d0 = price - c[j - 1];
   sd += d0; sdd += d0 * d0;
   double fit, sig, mn, ssd;
   bool   fl;
   return ComputeZ(sy, sxy, syy, y, sd, sdd, z_reg, z_sma, fit, sig, fl, mn, ssd);
}

void RememberBarZLabel(string name, datetime t) {
   for(int i = ArraySize(g_zl_names) - 1; i >= 0; i--)
      if(g_zl_names[i] == name) return;
   int n = ArraySize(g_zl_names);
   ArrayResize(g_zl_names, n + 1);
   ArrayResize(g_zl_times, n + 1);
   g_zl_names[n] = name;
   g_zl_times[n] = t;
}

// วาด/ลบป้าย Z ของแท่งเวลา t — zr/zs = Regression/SMA Z ที่ High [0] และ Low [1]
void SetBarZLabels(datetime t, double hi, double lo, const double &zr[], const double &zs[], const bool &ok[]) {
   double off = PtsToPrice(InpBarZOffset_Pts);
   string ts  = IntegerToString((long)t);

   for(int side = 0; side < 2; side++) {
      string name = OBJ_PREFIX + (side == 0 ? "ZL_S_" : "ZL_B_") + ts;
      bool   hit_r, hit_s;
      if(side == 0) { hit_r = zr[0] > InpT1_Z;  hit_s = zs[0] > InpT1_Z; }
      else          { hit_r = zr[1] < -InpT1_Z; hit_s = zs[1] < -InpT1_Z; }
      bool show = ok[side] && (hit_r || hit_s);
      if(!show) { if(ObjectFind(0, name) >= 0) ObjectDelete(0, name); continue; }

      int   tier       = TierOf(side == 0 ? -1 : 1, zr[side], zs[side]);
      bool  hit_active = (tier >= 1);
      color clr = !hit_active ? InpClrBarZOther : (side == 0 ? InpClrBarZSell : InpClrBarZBuy);
      double price = (side == 0) ? (hi + off) : (lo - off);

      if(ObjectFind(0, name) < 0) {
         ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
         ObjectSetString(0,  name, OBJPROP_FONT, "Arial Bold");
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpBarZFontSize);
         ObjectSetInteger(0, name, OBJPROP_ANCHOR, (side == 0) ? ANCHOR_LOWER : ANCHOR_UPPER);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
         RememberBarZLabel(name, t);
      }
      ObjectSetInteger(0, name, OBJPROP_TIME, t);
      ObjectSetDouble(0,  name, OBJPROP_PRICE, ND(price));
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetString(0,  name, OBJPROP_TEXT, StringFormat("R%+.2f | S%+.2f", zr[side], zs[side]));
      ObjectSetString(0,  name, OBJPROP_TOOLTIP,
                      StringFormat("%s | ที่ %s: Z_reg %+.2f%s / Z_SMA %+.2f%s | %s",
                                   TimeToString(t, TIME_DATE|TIME_MINUTES), (side == 0 ? "High" : "Low"),
                                   zr[side], (hit_r ? " ✓" : ""), zs[side], (hit_s ? " ✓" : ""),
                                   (hit_active ? "ถึงระดับ " + StageTag(tier) : "ถึงเกณฑ์ไม่ครบ")));
   }
}

// ประเมินแท่งที่ปิดแล้วชุดหนึ่ง (shift เริ่มที่ from_shift จำนวน bars แท่ง)
void EvaluateClosedBars(int from_shift, int bars) {
   int n   = InpZ_Period;
   int cnt = bars + n - 1;
   double c[], h[], l[];
   datetime t[];
   if(CopyClose(_Symbol, InpZ_Timeframe, from_shift, cnt, c) != cnt ||
      CopyHigh (_Symbol, InpZ_Timeframe, from_shift, cnt, h) != cnt ||
      CopyLow  (_Symbol, InpZ_Timeframe, from_shift, cnt, l) != cnt ||
      CopyTime (_Symbol, InpZ_Timeframe, from_shift, cnt, t) != cnt) return;

   double zr[2], zs[2];
   bool   ok[2];
   for(int j = n - 1; j < cnt; j++) {
      ok[0] = ZForBarPrice(c, j, h[j], zr[0], zs[0]);
      ok[1] = ZForBarPrice(c, j, l[j], zr[1], zs[1]);
      SetBarZLabels(t[j], h[j], l[j], zr, zs, ok);
   }
}

// ลบป้ายของแท่งที่เก่ากว่าช่วงที่แสดง
void PruneBarZLabels() {
   datetime cutoff = iTime(_Symbol, InpZ_Timeframe, InpBarZBars);
   if(cutoff == 0) return;
   int n = ArraySize(g_zl_names), w = 0;
   for(int i = 0; i < n; i++) {
      if(g_zl_times[i] < cutoff || ObjectFind(0, g_zl_names[i]) < 0) {
         ObjectDelete(0, g_zl_names[i]);
         continue;
      }
      g_zl_names[w] = g_zl_names[i];
      g_zl_times[w] = g_zl_times[i];
      w++;
   }
   if(w != n) { ArrayResize(g_zl_names, w); ArrayResize(g_zl_times, w); }
}

// เรียกทุก 1 วินาที: ขึ้นแท่งใหม่ → ยืนยันแท่งที่ปิด (หรือคำนวณย้อนหลังทั้งชุดครั้งแรก) + อัปเดตแท่งปัจจุบัน
void UpdateBarZLabels() {
   if(!g_draw || !InpShowBarZ || !g_z_ready) return;
   datetime t0 = CurrentZBarTime();
   if(t0 == 0) return;

   if(g_barz_bar == 0) {
      EvaluateClosedBars(1, InpBarZBars);
      g_barz_bar = t0;
   }
   else if(t0 != g_barz_bar) {
      EvaluateClosedBars(1, 1);   // ค่าจริงของแท่งที่เพิ่งปิด (เขียนทับป้ายสดเดิม)
      PruneBarZLabels();
      g_barz_bar = t0;
   }

   // แท่งปัจจุบัน: ใช้แคช Z สด + High/Low ที่ติดตามไว้
   double zr[2], zs[2], px[2];
   bool   ok[2];
   px[0] = g_bar0_hi;
   px[1] = g_bar0_lo;
   for(int s = 0; s < 2; s++) {
      double fit, sig, mn, ssd;
      bool   fl;
      zr[s] = 0.0; zs[s] = 0.0;
      ok[s] = (px[s] > 0.0) && ZAtPrice(g_zc, px[s], zr[s], zs[s], fit, sig, fl, mn, ssd);
   }
   SetBarZLabels(t0, g_bar0_hi, g_bar0_lo, zr, zs, ok);
}

//====================================================================
// 📍 มาร์กจุดเปิดไม้ + ระยะห่างถึงปลายไส้เทียน (TF ของ Z)
//====================================================================
struct EntryMark {
   ulong    deal;
   datetime t;
   double   price;
   int      dir;      // -1 SELL / 1 BUY
   bool     closed_bar;    // แท่งปิดแล้ว ระยะห่างคงที่
   string   cmt;
};
EntryMark g_marks[];

int FindMark(ulong deal) {
   for(int i = ArraySize(g_marks) - 1; i >= 0; i--)
      if(g_marks[i].deal == deal) return i;
   return -1;
}

void DrawEntryMark(EntryMark &m) {
   int shift = iBarShift(_Symbol, InpZ_Timeframe, m.t, false);
   if(shift < 0) return;
   double   hi  = iHigh(_Symbol, InpZ_Timeframe, shift);
   double   lo  = iLow (_Symbol, InpZ_Timeframe, shift);
   datetime bt  = iTime(_Symbol, InpZ_Timeframe, shift);
   if(hi <= 0.0 || lo <= 0.0) return;

   bool   is_sell = (m.dir == -1);
   double tip     = is_sell ? hi : lo;
   double gap     = is_sell ? (hi - m.price) : (m.price - lo);
   if(gap < 0.0) gap = 0.0;
   double gap_pts = PriceToPts(gap);
   double range   = hi - lo;
   string ds      = IntegerToString((long)m.deal);

   // 1. ลูกศรที่ราคาเปิดไม้
   string na = OBJ_PREFIX + "EN_A_" + ds;
   if(ObjectFind(0, na) < 0) {
      ObjectCreate(0, na, is_sell ? OBJ_ARROW_SELL : OBJ_ARROW_BUY, 0, m.t, m.price);
      ObjectSetInteger(0, na, OBJPROP_COLOR, is_sell ? InpClrEntrySell : InpClrEntryBuy);
      ObjectSetInteger(0, na, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, na, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, na, OBJPROP_HIDDEN, true);
   }

   // 2. เส้นประแนวตั้งจากราคาเปิดไม้ถึงปลายไส้
   string ng = OBJ_PREFIX + "EN_G_" + ds;
   if(ObjectFind(0, ng) < 0) {
      ObjectCreate(0, ng, OBJ_TREND, 0, m.t, m.price, m.t, tip);
      ObjectSetInteger(0, ng, OBJPROP_COLOR, InpClrEntryGap);
      ObjectSetInteger(0, ng, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, ng, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, ng, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, ng, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, ng, OBJPROP_HIDDEN, true);
   }
   ObjectMove(0, ng, 1, m.t, tip);

   // 3. ตัวเลขระยะห่าง
   string nt = OBJ_PREFIX + "EN_T_" + ds;
   if(ObjectFind(0, nt) < 0) {
      ObjectCreate(0, nt, OBJ_TEXT, 0, m.t, m.price);
      ObjectSetString(0,  nt, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, nt, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, nt, OBJPROP_COLOR, InpClrEntryGap);
      ObjectSetInteger(0, nt, OBJPROP_ANCHOR, ANCHOR_LEFT);
      ObjectSetInteger(0, nt, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nt, OBJPROP_HIDDEN, true);
   }
   ObjectSetString(0, nt, OBJPROP_TEXT, StringFormat("   %s ห่างไส้ %.0f", (is_sell ? "S" : "B"), gap_pts));

   string tipText = StringFormat("%s @ %s | %s แท่ง %s = %s | ห่างปลายไส้ %.0f จุด (%.0f%% ของช่วงแท่ง)%s | %s",
                                 (is_sell ? "SELL" : "BUY"), DoubleToString(m.price, _Digits),
                                 (is_sell ? "High" : "Low"), TimeToString(bt, TIME_DATE|TIME_MINUTES),
                                 DoubleToString(tip, _Digits), gap_pts, (range > 0.0 ? 100.0 * gap / range : 0.0),
                                 (shift == 0 ? " (แท่งยังไม่ปิด)" : ""), m.cmt);
   ObjectSetString(0, na, OBJPROP_TOOLTIP, tipText);
   ObjectSetString(0, ng, OBJPROP_TOOLTIP, tipText);
   ObjectSetString(0, nt, OBJPROP_TOOLTIP, tipText);

   m.closed_bar = (shift > 0);
}

// เพิ่มมาร์กจาก deal เปิดไม้ของ EA (deal ต้องถูกเลือกใน history แล้ว)
void AddEntryMarkFromDeal(ulong deal) {
   if(!g_draw || !InpShowEntryMarks) return;
   if(HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagic) return;
   if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol) return;
   if(HistoryDealGetInteger(deal, DEAL_ENTRY) != DEAL_ENTRY_IN) return;
   long type = HistoryDealGetInteger(deal, DEAL_TYPE);
   if(type != DEAL_TYPE_BUY && type != DEAL_TYPE_SELL) return;
   if(FindMark(deal) >= 0) return;

   int n = ArraySize(g_marks);
   ArrayResize(g_marks, n + 1);
   g_marks[n].deal  = deal;
   g_marks[n].t     = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
   g_marks[n].price = HistoryDealGetDouble(deal, DEAL_PRICE);
   g_marks[n].dir   = (type == DEAL_TYPE_SELL) ? -1 : 1;
   g_marks[n].closed_bar = false;
   g_marks[n].cmt   = HistoryDealGetString(deal, DEAL_COMMENT);
   DrawEntryMark(g_marks[n]);
}

// โหลดไม้ย้อนหลังจาก Deal History เท่าช่วงป้าย Z
void LoadEntryMarksFromHistory() {
   if(!g_draw || !InpShowEntryMarks) return;
   datetime from = iTime(_Symbol, InpZ_Timeframe, InpBarZBars);
   if(from == 0) from = ServerNow() - (datetime)(PeriodSeconds(InpZ_Timeframe) * InpBarZBars);
   if(!HistorySelect(from, ServerNow() + 60)) return;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++) {
      ulong deal = HistoryDealGetTicket(i);
      if(deal > 0) AddEntryMarkFromDeal(deal);
   }
}

void DeleteEntryMarkObjects(ulong deal) {
   string ds = IntegerToString((long)deal);
   ObjectDelete(0, OBJ_PREFIX + "EN_A_" + ds);
   ObjectDelete(0, OBJ_PREFIX + "EN_G_" + ds);
   ObjectDelete(0, OBJ_PREFIX + "EN_T_" + ds);
}

// ทุก 1 วินาที: อัปเดตระยะห่างของมาร์กในแท่งที่ยังไม่ปิด + ลบมาร์กที่เก่าเกินช่วง (ตอนขึ้นแท่งใหม่)
datetime g_marks_bar = 0;
void UpdateEntryMarks() {
   if(!g_draw || !InpShowEntryMarks) return;
   for(int i = ArraySize(g_marks) - 1; i >= 0; i--)
      if(!g_marks[i].closed_bar) DrawEntryMark(g_marks[i]);

   datetime t0 = CurrentZBarTime();
   if(t0 == 0 || t0 == g_marks_bar) return;
   g_marks_bar = t0;
   datetime cutoff = iTime(_Symbol, InpZ_Timeframe, InpBarZBars);
   if(cutoff == 0) return;
   int n = ArraySize(g_marks), w = 0;
   for(int i = 0; i < n; i++) {
      if(g_marks[i].t < cutoff) { DeleteEntryMarkObjects(g_marks[i].deal); continue; }
      g_marks[w++] = g_marks[i];
   }
   if(w != n) ArrayResize(g_marks, w);
}

//====================================================================
// 🧪 TICK REPLAY — เล่นซ้ำ tick จริงด้วยกติกาเดียวกับ EA
//   (T1 15 วิ / T2 5 วิ / T3 ทันที / นาทีแรก + ท้ายแท่ง / ข่าว / ครั้งละ 1 ไม้ / Cool down / TP / SL / โล่ / คืนกำไร / ตัดเวลา / ปิดสุดสัปดาห์)
//====================================================================
#define RX_OPEN   0
#define RX_TP     1
#define RX_SL     2
#define RX_CUT    3
#define RX_TRAIL  4
#define RX_WEEK   5
#define RX_GIVE   6

struct RTrade {
   long     msc_in;
   int      dir;
   int      stage;         // ระดับวิกฤตที่ยิง (1-3)
   int      max_tier;      // ระดับลึกสุดระหว่างเฝ้า
   double   lot;
   double   p_in, sl, tp;
   double   zr, zs, ext_r, ext_s;
   double   mfe, mae;      // กำไรสูงสุด / ติดลบสูงสุดระหว่างถือ (ราคา)
   double   sl0;           // SL ตอนเปิดไม้ (ก่อนขยับโล่)
   bool     activated;
   long     last_trail_sec;
   datetime force_close;
   long     msc_out;
   double   p_out;
   int      reason;
   double   pnl;           // จุด
   double   usd;           // $ ตาม Lot
   bool     drawn_final;
};

struct RBlocked {
   long   msc;
   int    dir;
   double price;
   string why;
};

// จุดเริ่ม Cool down (สำหรับวาด)
struct RCool {
   long     msc;
   int      tier;
   double   price;
   datetime until;
};

RTrade     g_rt[];
RBlocked   g_rb[];
RCool      g_rc[];
int        g_rt_open      = -1;
int        g_rb_drawn     = 0;
int        g_rc_drawn     = 0;
CoolState  g_rp_cool;

MqlRates   g_rr[];
int        g_rp_b         = -1;
datetime   g_rp_bar_t     = 0;
ZCache     g_rp_zc;
bool       g_rp_bar_chg   = false;
double     g_rp_hi        = 0.0;     // High / Low ของแท่งปัจจุบัน (จาก tick ที่เล่นมาแล้ว) สำหรับวาง SL
double     g_rp_lo        = 0.0;
WatchState g_rp_ws;
WatchState g_rp_wb;
double     g_rp_bid = 0.0, g_rp_ask = 0.0, g_rp_zr = 0.0, g_rp_zs = 0.0;
long       g_rp_msc       = 0;
bool       g_rp_have      = false;
bool       g_rp_init      = false;
bool       g_rp_caught    = false;
long       g_rp_cursor    = 0;
int        g_rp_retry     = 0;
int        g_rp_news_wait = 0;      // วินาทีที่รอปฏิทินข่าวก่อนเริ่มเล่นซ้ำ
long       g_rp_ticks     = 0;
string     g_rp_status    = "ยังไม่เริ่ม";
double     g_contract     = 100.0;

void ReplayReset() {
   ArrayResize(g_rt, 0);
   ArrayResize(g_rb, 0);
   ArrayResize(g_rc, 0);
   ArrayResize(g_rr, 0);
   g_rt_open = -1; g_rb_drawn = 0; g_rc_drawn = 0;
   CoolReset(g_rp_cool);
   g_rp_b = -1; g_rp_bar_t = 0; g_rp_zc.ok = false; g_rp_bar_chg = false; g_rp_hi = 0.0; g_rp_lo = 0.0;
   WatchReset(g_rp_ws); WatchReset(g_rp_wb);
   g_rp_bid = 0.0; g_rp_ask = 0.0; g_rp_zr = 0.0; g_rp_zs = 0.0;
   g_rp_msc = 0; g_rp_have = false; g_rp_init = false; g_rp_caught = false;
   g_rp_cursor = 0; g_rp_retry = 0; g_rp_ticks = 0; g_rp_news_wait = 0;
   g_rp_status = "ยังไม่เริ่ม";
}

bool ReplayLoadRates() {
   int per_day = (int)(DAY_SEC / MathMax(60, PeriodSeconds(InpZ_Timeframe)));
   int count   = (InpReplayDays + 4) * per_day + InpZ_Period + 10;
   int got = CopyRates(_Symbol, InpZ_Timeframe, 0, count, g_rr);
   return (got > InpZ_Period + 3);
}

// เข้าแท่งใหม่ (TF ของ Z): สร้างแคช Z
void ReplayEnterBar(int b) {
   g_rp_b = b;
   if(g_rr[b].time == g_rp_bar_t) return;
   bool had   = (g_rp_bar_t != 0);
   g_rp_bar_t = g_rr[b].time;
   g_rp_zc.ok = false;
   g_rp_hi    = 0.0;
   g_rp_lo    = 0.0;
   int n = InpZ_Period;
   if(b >= n) {
      double c[];
      ArrayResize(c, n);
      for(int i = 0; i < n; i++) c[i] = g_rr[b - n + i].close;
      BuildZCache(c, g_rp_zc);
   }
   if(had) g_rp_bar_chg = true;
}

bool ReplayBarFor(datetime t) {
   int n = ArraySize(g_rr);
   if(n == 0) return false;
   if(t >= g_rr[n - 1].time + (datetime)PeriodSeconds(InpZ_Timeframe)) {
      if(!ReplayLoadRates()) return false;
      n = ArraySize(g_rr);
      g_rp_b = -1;
   }
   if(g_rp_b < 0 || g_rp_b >= n || g_rr[g_rp_b].time > t) {
      int b = -1;
      for(int i = n - 1; i >= 0; i--) if(g_rr[i].time <= t) { b = i; break; }
      if(b < 0) return false;
      ReplayEnterBar(b);
      return true;
   }
   int b = g_rp_b;
   while(b + 1 < n && g_rr[b + 1].time <= t) b++;
   ReplayEnterBar(b);
   return true;
}

int ReplayOpen(int dir, int stage, long msc, double price) {
   int i = ArraySize(g_rt);
   ArrayResize(g_rt, i + 1);
   double hi   = (g_rp_hi > 0.0) ? MathMax(g_rp_hi, price) : price;
   double lo   = (g_rp_lo > 0.0) ? MathMin(g_rp_lo, price) : price;
   double tp_d = PtsToPrice(InpTP_Pts);
   g_rt[i].msc_in   = msc;
   g_rt[i].dir      = dir;
   g_rt[i].stage    = stage;
   g_rt[i].lot      = TierLot(stage);
   g_rt[i].max_tier = stage;
   g_rt[i].p_in     = price;
   g_rt[i].sl       = SLPrice(dir, hi, lo, stage);
   g_rt[i].tp       = (dir == -1) ? price - tp_d : price + tp_d;
   g_rt[i].zr       = g_rp_zr;
   g_rt[i].zs       = g_rp_zs;
   g_rt[i].ext_r    = 0.0;
   g_rt[i].ext_s    = 0.0;
   g_rt[i].mfe = 0.0; g_rt[i].mae = 0.0;
   g_rt[i].sl0      = g_rt[i].sl;
   g_rt[i].activated      = false;
   g_rt[i].last_trail_sec = 0;
   g_rt[i].force_close    = ForceCloseTimeAt((datetime)(msc / 1000));
   g_rt[i].msc_out  = 0;
   g_rt[i].p_out    = 0.0;
   g_rt[i].reason   = RX_OPEN;
   g_rt[i].pnl      = 0.0;
   g_rt[i].usd      = 0.0;
   g_rt[i].drawn_final = false;
   g_rt_open = i;
   WatchReset(g_rp_ws);
   WatchReset(g_rp_wb);
   return i;
}

// ปิดไม้จำลอง + นับ SL ของ T2 / T3 (ครบ → เริ่ม Cool down)
void ReplayClose(long msc_out, double price, int reason) {
   int i = g_rt_open;
   if(i < 0) return;
   g_rt[i].msc_out = msc_out;
   g_rt[i].p_out   = price;
   g_rt[i].reason  = reason;
   double diff     = (g_rt[i].dir == -1) ? (g_rt[i].p_in - price) : (price - g_rt[i].p_in);
   g_rt[i].pnl     = PriceToPts(diff);
   g_rt[i].usd     = diff * g_rt[i].lot * g_contract;
   g_rt_open = -1;
   if(CoolOnClose(g_rp_cool, g_rt[i].stage, reason == RX_SL && diff < 0.0, (datetime)(msc_out / 1000))) {
      int k = ArraySize(g_rc);
      ArrayResize(g_rc, k + 1);
      g_rc[k].msc = msc_out; g_rc[k].tier = g_rt[i].stage; g_rc[k].price = price; g_rc[k].until = g_rp_cool.until;
   }
}

void ReplayFire(int dir, long fire_msc) {
   WatchState w;
   if(dir == -1) w = g_rp_ws; else w = g_rp_wb;
   datetime t   = (datetime)(fire_msc / 1000);
   int      tier = w.tier;
   string   why = TimeBlockReason(t);
   if(why == "") why = EntryBlockReason(GetTimeStateAt(t), g_rp_bid, g_rp_ask);
   if(why != "") {
      int k = ArraySize(g_rb);
      ArrayResize(g_rb, k + 1);
      g_rb[k].msc = fire_msc; g_rb[k].dir = dir; g_rb[k].why = StageTag(tier) + ": " + why;
      g_rb[k].price = (dir == -1) ? g_rp_bid : g_rp_ask;
      if(dir == -1) WatchReset(g_rp_ws); else WatchReset(g_rp_wb);
      return;
   }
   int i = ReplayOpen(dir, tier, fire_msc, (dir == -1) ? g_rp_bid : g_rp_ask);
   g_rt[i].ext_r = w.ext_r;
   g_rt[i].ext_s = w.ext_s;
}

// เหตุการณ์ตามเวลาระหว่าง tick ก่อนหน้า → tick นี้ (ราคายังเป็นของ tick ก่อนหน้า)
void ReplayTimeEvents(long msc) {
   if(!g_rp_have) return;
   if(g_rt_open >= 0) {
      int  i   = g_rt_open;
      long wk  = (g_rt[i].force_close > 0) ? (long)g_rt[i].force_close * 1000 : LONG_MAX;
      long cut = (InpQuickWindow_Sec > 0 && !g_rt[i].activated) ? g_rt[i].msc_in + (long)InpQuickWindow_Sec * 1000 : LONG_MAX;
      double px = (g_rt[i].dir == -1) ? g_rp_ask : g_rp_bid;
      if(wk <= cut && wk <= msc)       ReplayClose(wk,  px, RX_WEEK);
      else if(cut < wk && cut <= msc)  ReplayClose(cut, px, RX_CUT);
      return;
   }
   // ครบเวลาเฝ้า (ราคาของ tick ก่อนหน้า) → ยิง
   if(WatchReady(g_rp_ws, msc))      ReplayFire(-1, MathMax(WatchDeadline(g_rp_ws), g_rp_msc));
   else if(WatchReady(g_rp_wb, msc)) ReplayFire( 1, MathMax(WatchDeadline(g_rp_wb), g_rp_msc));
}

// ไม้ที่ถืออยู่: SL / TP / คืนกำไร / โล่ ด้วยราคา tick ปัจจุบัน// ไม้ที่ถืออยู่: SL / TP / โล่ ด้วยราคา tick ปัจจุบัน
void ReplayManageTick(long msc, double bid, double ask) {
   int i = g_rt_open;
   if(i < 0) return;
   int d = g_rt[i].dir;
   double fav = (d == -1) ? (g_rt[i].p_in - ask) : (bid - g_rt[i].p_in);
   if(fav > g_rt[i].mfe) g_rt[i].mfe = fav;
   if(fav < g_rt[i].mae) g_rt[i].mae = fav;
   if(d == -1) {
      if(g_rt[i].sl > 0.0 && ask >= g_rt[i].sl) { ReplayClose(msc, ask, g_rt[i].activated ? RX_TRAIL : RX_SL); return; }
      if(g_rt[i].tp > 0.0 && ask <= g_rt[i].tp) { ReplayClose(msc, g_rt[i].tp, RX_TP); return; }
   } else {
      if(g_rt[i].sl > 0.0 && bid <= g_rt[i].sl) { ReplayClose(msc, bid, g_rt[i].activated ? RX_TRAIL : RX_SL); return; }
      if(g_rt[i].tp > 0.0 && bid >= g_rt[i].tp) { ReplayClose(msc, g_rt[i].tp, RX_TP); return; }
   }
   double prof = (d == -1) ? (g_rt[i].p_in - ask) : (bid - g_rt[i].p_in);
   if(!g_rt[i].activated && GivebackHit(g_rt[i].mfe, prof)) { ReplayClose(msc, (d == -1) ? ask : bid, RX_GIVE); return; }
   long   sec  = msc / 1000;
   bool   do_trail = false;
   if(!g_rt[i].activated) {
      if(prof >= PtsToPrice(InpTrailStart_Pts)) { g_rt[i].activated = true; do_trail = true; }
   }
   else if(sec - g_rt[i].last_trail_sec >= InpTrailInterval_Sec) do_trail = true;
   if(do_trail) {
      double dist = PtsToPrice(InpTrailDist_Pts);
      if(d == -1) { double nsl = ask + dist; if(g_rt[i].sl <= 0.0 || nsl < g_rt[i].sl) g_rt[i].sl = nsl; }
      else        { double nsl = bid - dist; if(nsl > g_rt[i].sl) g_rt[i].sl = nsl; }
      g_rt[i].last_trail_sec = sec;
   }
}

void ReplayTick(const MqlTick &tk) {
   double bid = tk.bid, ask = tk.ask;
   if(bid <= 0.0 || ask <= 0.0) return;
   long     msc = (long)tk.time_msc;
   datetime t   = (datetime)(msc / 1000);

   ReplayTimeEvents(msc);                 // A) เหตุการณ์ตามเวลาด้วยราคาเดิม (ตัดเวลา / ยิงหลังครบเวลาเฝ้า)
   if(!ReplayBarFor(t)) return;           // B) แท่งของ tick นี้
   if(g_rp_hi <= 0.0 || bid > g_rp_hi) g_rp_hi = bid;
   if(g_rp_lo <= 0.0 || bid < g_rp_lo) g_rp_lo = bid;

   double zr = 0.0, zs = 0.0, fit, sig, mn, ssd;
   bool   fl;
   bool   zok = ZAtPrice(g_rp_zc, bid, zr, zs, fit, sig, fl, mn, ssd);
   if(zok) { g_rp_zr = zr; g_rp_zs = zs; }

   if(g_rt_open >= 0) ReplayManageTick(msc, bid, ask);   // C) ไม้ที่ถืออยู่

   // D) เฝ้าค่าสุดขั้ว: ไม่มีไม้ + ไม่อยู่ในช่วงห้าม (นาทีแรก / ท้ายแท่ง / ข่าว) + ไม่ได้พัก (ขึ้นแท่งใหม่ล้างการเฝ้า)
   bool idle    = (g_rt_open < 0);
   bool blocked = (TimeBlockReason(t) != "");
   bool cool    = CoolActive(g_rp_cool, t);
   if(!idle || blocked || cool || !zok || g_rp_bar_chg) { WatchReset(g_rp_ws); WatchReset(g_rp_wb); }
   if(idle && !blocked && !cool && zok) {
      WatchUpdate(g_rp_ws, -1, zr, zs, msc, bid);
      WatchUpdate(g_rp_wb,  1, zr, zs, msc, bid);
   }
   g_rp_bar_chg = false;

   g_rp_bid = bid; g_rp_ask = ask; g_rp_msc = msc;
   g_rp_have = true;
   g_rp_ticks++;
}

string ReplayReasonName(int r) {
   switch(r) {
      case RX_TP:    return "TP";
      case RX_SL:    return "SL";
      case RX_CUT:   return "ตัดเวลา";
      case RX_TRAIL: return "โล่";
      case RX_WEEK:  return "ปิดสัปดาห์";
      case RX_GIVE:  return "คืนกำไร";
   }
   return "ถืออยู่";
}

void DrawReplayTrade(int i) {
   datetime t_in    = (datetime)(g_rt[i].msc_in / 1000);
   bool     is_sell = (g_rt[i].dir == -1);
   string   id      = IntegerToString(g_rt[i].msc_in) + "_" + IntegerToString(i);
   int      shift   = iBarShift(_Symbol, InpZ_Timeframe, t_in, false);
   double   hi = (shift >= 0) ? iHigh(_Symbol, InpZ_Timeframe, shift) : 0.0;
   double   lo = (shift >= 0) ? iLow (_Symbol, InpZ_Timeframe, shift) : 0.0;
   double   tip = is_sell ? hi : lo;
   double   gap = (tip > 0.0) ? PriceToPts(MathAbs(tip - g_rt[i].p_in)) : 0.0;
   bool     open = (g_rt[i].reason == RX_OPEN);
   color    clr  = is_sell ? InpClrSimSell : InpClrSimBuy;
   string   tag  = StageTag(g_rt[i].stage);

   string na = OBJ_PREFIX + "RP_A_" + id, ng = OBJ_PREFIX + "RP_G_" + id;
   string nl = OBJ_PREFIX + "RP_L_" + id, nt = OBJ_PREFIX + "RP_T_" + id;

   if(ObjectFind(0, na) < 0) {
      ObjectCreate(0, na, is_sell ? OBJ_ARROW_SELL : OBJ_ARROW_BUY, 0, t_in, g_rt[i].p_in);
      ObjectSetInteger(0, na, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, na, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, na, OBJPROP_HIDDEN, true);
   }
   if(tip > 0.0) {
      if(ObjectFind(0, ng) < 0) {
         ObjectCreate(0, ng, OBJ_TREND, 0, t_in, g_rt[i].p_in, t_in, tip);
         ObjectSetInteger(0, ng, OBJPROP_COLOR, clr);
         ObjectSetInteger(0, ng, OBJPROP_STYLE, STYLE_DOT);
         ObjectSetInteger(0, ng, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(0, ng, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, ng, OBJPROP_HIDDEN, true);
      }
      ObjectMove(0, ng, 1, t_in, tip);
   }
   if(!open) {
      datetime t_out = (datetime)(g_rt[i].msc_out / 1000);
      if(ObjectFind(0, nl) < 0) {
         ObjectCreate(0, nl, OBJ_TREND, 0, t_in, g_rt[i].p_in, t_out, g_rt[i].p_out);
         ObjectSetInteger(0, nl, OBJPROP_STYLE, STYLE_DASH);
         ObjectSetInteger(0, nl, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(0, nl, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, nl, OBJPROP_HIDDEN, true);
      }
      ObjectSetInteger(0, nl, OBJPROP_COLOR, (g_rt[i].pnl > 0.0) ? InpClrSimWin : InpClrSimLoss);
   }
   if(ObjectFind(0, nt) < 0) {
      ObjectCreate(0, nt, OBJ_TEXT, 0, t_in, g_rt[i].p_in);
      ObjectSetString(0,  nt, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, nt, OBJPROP_FONTSIZE, 7);
      ObjectSetInteger(0, nt, OBJPROP_ANCHOR, ANCHOR_RIGHT);
      ObjectSetInteger(0, nt, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nt, OBJPROP_HIDDEN, true);
   }
   ObjectSetInteger(0, nt, OBJPROP_COLOR, open ? clr : ((g_rt[i].pnl > 0.0) ? InpClrSimWin : InpClrSimLoss));
   ObjectSetString(0, nt, OBJPROP_TEXT,
                   open ? StringFormat("%s %s %.2f | ห่างไส้ %.0f | ถืออยู่   ", tag, (is_sell ? "S" : "B"), g_rt[i].lot, gap)
                        : StringFormat("%s %s %.2f | ห่างไส้ %.0f | %s %+.0f ($%+.2f)   ", tag, (is_sell ? "S" : "B"), g_rt[i].lot, gap,
                                       ReplayReasonName(g_rt[i].reason), g_rt[i].pnl, g_rt[i].usd));

   string tipText = StringFormat("จำลอง %s %s %.2f lot @ %s (%s)\nZ ตอนเข้า R %+.2f / S %+.2f",
                                 tag, (is_sell ? "SELL" : "BUY"), g_rt[i].lot, DoubleToString(g_rt[i].p_in, _Digits),
                                 TimeToString(t_in, TIME_DATE|TIME_SECONDS), g_rt[i].zr, g_rt[i].zs);
   tipText += StringFormat(" | สุดขั้วระหว่างเฝ้า R %+.2f / S %+.2f | ลึกสุด T%d", g_rt[i].ext_r, g_rt[i].ext_s, g_rt[i].max_tier);
   tipText += StringFormat("\nห่างปลายไส้ %.0f จุด | SL ตอนเข้า %s (ไส้ ± %.0f จุด)", gap, DoubleToString(g_rt[i].sl0, _Digits), SLBeyondPts(g_rt[i].stage));
   if(!open)
      tipText += StringFormat("\nออก %s @ %s (%s) | %+.0f จุด | $%+.2f | ถือ %d วินาที",
                              ReplayReasonName(g_rt[i].reason), DoubleToString(g_rt[i].p_out, _Digits),
                              TimeToString((datetime)(g_rt[i].msc_out / 1000), TIME_DATE|TIME_SECONDS),
                              g_rt[i].pnl, g_rt[i].usd, (int)((g_rt[i].msc_out - g_rt[i].msc_in) / 1000))
               + StringFormat(" | MFE %+.0f / MAE %+.0f จุด", PriceToPts(g_rt[i].mfe), PriceToPts(g_rt[i].mae));
   ObjectSetString(0, na, OBJPROP_TOOLTIP, tipText);
   ObjectSetString(0, nt, OBJPROP_TOOLTIP, tipText);
   if(tip > 0.0)  ObjectSetString(0, ng, OBJPROP_TOOLTIP, tipText);
   if(!open)      ObjectSetString(0, nl, OBJPROP_TOOLTIP, tipText);

   g_rt[i].drawn_final = (!open && shift > 0);
}

void DrawReplayBlocked(int k) {
   datetime t  = (datetime)(g_rb[k].msc / 1000);
   string   nx = OBJ_PREFIX + "RP_X_" + IntegerToString(g_rb[k].msc) + (g_rb[k].dir == -1 ? "_S" : "_B");
   if(ObjectFind(0, nx) < 0) {
      ObjectCreate(0, nx, OBJ_ARROW, 0, t, g_rb[k].price);
      ObjectSetInteger(0, nx, OBJPROP_ARROWCODE, 251);   // ×
      ObjectSetInteger(0, nx, OBJPROP_COLOR, InpClrSimBlocked);
      ObjectSetInteger(0, nx, OBJPROP_ANCHOR, ANCHOR_CENTER);
      ObjectSetInteger(0, nx, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nx, OBJPROP_HIDDEN, true);
   }
   ObjectSetString(0, nx, OBJPROP_TOOLTIP,
                   StringFormat("สัญญาณ %s ถูกทิ้ง %s @ %s\nเหตุผล: %s", (g_rb[k].dir == -1 ? "SELL" : "BUY"),
                                TimeToString(t, TIME_DATE|TIME_SECONDS), DoubleToString(g_rb[k].price, _Digits), g_rb[k].why));
}

void DrawReplayCool(int k) {
   datetime t  = (datetime)(g_rc[k].msc / 1000);
   string   nm = OBJ_PREFIX + "RP_C_" + IntegerToString(g_rc[k].msc);
   if(ObjectFind(0, nm) < 0) {
      ObjectCreate(0, nm, OBJ_TEXT, 0, t, g_rc[k].price);
      ObjectSetString(0,  nm, OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, nm, OBJPROP_COLOR, InpClrSimCool);
      ObjectSetInteger(0, nm, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
   }
   int need = (g_rc[k].tier >= 3) ? InpCoolT3_SL : InpCoolT2_SL;
   ObjectSetString(0, nm, OBJPROP_TEXT, StringFormat("  พัก %d นาที (SL %s ×%d)", InpCooldown_Min, StageTag(g_rc[k].tier), need));
   ObjectSetString(0, nm, OBJPROP_TOOLTIP, StringFormat("Cool down: ชน SL ของ %s %d ครั้ง → หยุดเฝ้า/เปิดไม้ %s ถึง %s",
                   StageTag(g_rc[k].tier), need, TimeToString(t, TIME_DATE|TIME_MINUTES), TimeToString(g_rc[k].until, TIME_DATE|TIME_MINUTES)));
}

void ReplayDraw() {
   for(int i = 0; i < ArraySize(g_rt); i++)
      if(!g_rt[i].drawn_final) DrawReplayTrade(i);
   for(; g_rc_drawn < ArraySize(g_rc); g_rc_drawn++) DrawReplayCool(g_rc_drawn);
   if(InpShowReplayBlocked)
      for(; g_rb_drawn < ArraySize(g_rb); g_rb_drawn++) DrawReplayBlocked(g_rb_drawn);
}

string ReplayStatsText() {
   if(!InpShowReplay) return "";
   int    n = 0, w = 0, c_tp = 0, c_sl = 0, c_cut = 0, c_tr = 0, c_wk = 0, c_gb = 0;
   int    cnt[4];
   double usd_st[4];
   ArrayInitialize(cnt, 0);
   ArrayInitialize(usd_st, 0.0);
   double usd = 0.0, peak = 0.0, dd = 0.0;
   for(int i = 0; i < ArraySize(g_rt); i++) {
      if(g_rt[i].reason == RX_OPEN) continue;
      n++;
      if(g_rt[i].usd > 0.0) w++;
      usd += g_rt[i].usd;
      if(usd > peak) peak = usd;
      if(usd - peak < dd) dd = usd - peak;
      int st = MathMax(1, MathMin(3, g_rt[i].stage));
      cnt[st]++;
      usd_st[st] += g_rt[i].usd;
      switch(g_rt[i].reason) {
         case RX_TP: c_tp++; break;   case RX_SL: c_sl++; break;   case RX_CUT: c_cut++; break;
         case RX_TRAIL: c_tr++; break; case RX_WEEK: c_wk++; break; case RX_GIVE: c_gb++; break;
      }
   }
   string s = StringFormat("🧪 Replay %d วัน: %s\n   %d ไม้ | ชนะ %.0f%% | กำไรสุทธิ $%+.2f | DD $%.2f | TP %d SL %d โล่ %d คืนกำไร %d ตัดเวลา %d ปิดสัปดาห์ %d | ถูกทิ้ง %d",
                           InpReplayDays, g_rp_status, n, (n > 0 ? 100.0 * w / n : 0.0), usd, dd,
                           c_tp, c_sl, c_tr, c_gb, c_cut, c_wk, ArraySize(g_rb));
   string tail = "";
   if(g_rt_open >= 0)                                          tail = " | มีไม้จำลองถืออยู่";
   else if(CoolActive(g_rp_cool, (datetime)(g_rp_msc / 1000))) tail = " | จำลองกำลังพัก";
   s += StringFormat("\n   T1 %d ไม้ ($%+.2f) | T2 %d ไม้ ($%+.2f) | T3 %d ไม้ ($%+.2f) | Cool down %d ครั้ง%s",
                     cnt[1], usd_st[1], cnt[2], usd_st[2], cnt[3], usd_st[3], ArraySize(g_rc), tail);
   return s;
}

// เรียกทุก 1 วินาที: ไล่เล่นซ้ำทีละช่วง (ครั้งแรกทีละ 12 ชม.) จนถึงปัจจุบัน แล้วต่อแบบสด
void ReplayStep() {
   if(!g_draw || !InpShowReplay) return;
   if(!g_rp_init) {
      if(NewsFilterOn() && !g_news_ok && g_rp_news_wait < 60) {   // ให้ตัวกรองข่าวมีผลตั้งแต่วันแรกของการเล่นซ้ำ
         g_rp_news_wait++;
         g_rp_status = "⏳ รอโหลดปฏิทินข่าว";
         return;
      }
      if(!ReplayLoadRates()) { g_rp_status = "⏳ รอประวัติแท่ง"; return; }
      g_contract  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
      if(g_contract <= 0.0) g_contract = 100.0;
      g_rp_cursor = ((long)TimeCurrent() - (long)InpReplayDays * DAY_SEC) * 1000;
      g_rp_init   = true;
   }
   long now_msc = (long)TimeCurrent() * 1000 + 999;
   if(g_last_tick_msc > now_msc) now_msc = g_last_tick_msc;

   long chunk = g_rp_caught ? (now_msc - g_rp_cursor) : (long)DAY_SEC * 500;   // 12 ชม.
   long to    = MathMin(g_rp_cursor + chunk, now_msc);
   if(to >= g_rp_cursor) {
      MqlTick ticks[];
      int got = CopyTicksRange(_Symbol, ticks, COPY_TICKS_INFO, (ulong)g_rp_cursor, (ulong)to);
      if(got < 0) { g_rp_status = StringFormat("⏳ กำลังโหลด tick (error %d)", GetLastError()); return; }
      if(got == 0 && !g_rp_caught && g_rp_retry < 3 &&
         GetTimeStateAt((datetime)((g_rp_cursor + to) / 2000)) != TS_CLOSED) {
         g_rp_retry++;   // ตลาดน่าจะเปิดแต่ยังไม่ได้ tick → รอโหลดอีกนิด
         return;
      }
      g_rp_retry = 0;
      for(int k = 0; k < got; k++) {
         if((long)ticks[k].time_msc < g_rp_cursor) continue;
         ReplayTick(ticks[k]);
      }
      if(got > 0)            g_rp_cursor = (long)ticks[got - 1].time_msc + 1;
      else if(!g_rp_caught)  g_rp_cursor = to + 1;
   }
   if(!g_rp_caught && to >= now_msc - 2000) g_rp_caught = true;
   if(g_rp_caught) ReplayTimeEvents(now_msc);   // เวลาผ่านไปโดยไม่มี tick (ตัดเวลา / ยิงหลังครบเวลาเฝ้า)

   g_rp_status = g_rp_caught
                 ? StringFormat("✅ ครบแล้ว + เดินต่อแบบสด (%I64d ticks)", g_rp_ticks)
                 : StringFormat("⏳ กำลังเล่นซ้ำ ถึง %s (%I64d ticks)", TimeToString((datetime)(g_rp_cursor / 1000), TIME_DATE|TIME_MINUTES), g_rp_ticks);
   ReplayDraw();
}

//====================================================================
// 📰 ข่าวบนกราฟ: เส้นเวลาข่าว + แถบแท่งข่าว (ย้อนหลังเท่าช่วงป้าย Z + 24 ชม.ข้างหน้า)
//====================================================================
datetime g_newsviz_loaded = 0;
string   g_newsviz_names[];

void DrawNewsEvent(datetime t, string title, string detail) {
   string ts = IntegerToString((long)t);
   string nv = OBJ_PREFIX + "NEWS_V_" + ts;
   string nz = OBJ_PREFIX + "NEWS_Z_" + ts;

   if(ObjectFind(0, nv) < 0) {
      ObjectCreate(0, nv, OBJ_VLINE, 0, t, 0);
      ObjectSetInteger(0, nv, OBJPROP_COLOR, InpClrNewsLine);
      ObjectSetInteger(0, nv, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(0, nv, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, nv, OBJPROP_BACK, true);
      ObjectSetInteger(0, nv, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nv, OBJPROP_HIDDEN, true);
      ObjectSetString(0,  nv, OBJPROP_TOOLTIP, detail);
      ObjectSetString(0,  nv, OBJPROP_TEXT, title);
      int n = ArraySize(g_newsviz_names);
      ArrayResize(g_newsviz_names, n + 2);
      g_newsviz_names[n] = nv; g_newsviz_names[n + 1] = nz;
   }
   else {
      string old = ObjectGetString(0, nv, OBJPROP_TOOLTIP);
      if(StringFind(old, detail) < 0) ObjectSetString(0, nv, OBJPROP_TOOLTIP, old + "\n" + detail);
   }

   if(ObjectFind(0, nz) < 0) {
      double   top = SymbolInfoDouble(_Symbol, SYMBOL_BID) * 10.0;
      long     per = MathMax(60, PeriodSeconds(InpZ_Timeframe));
      datetime b0  = t - (datetime)((long)t % per);   // แท่งข่าว (TF ของ Z)
      ObjectCreate(0, nz, OBJ_RECTANGLE, 0, b0, 0.0, b0 + (datetime)per, top);
      ObjectSetInteger(0, nz, OBJPROP_COLOR, InpClrNewsZone);
      ObjectSetInteger(0, nz, OBJPROP_FILL, true);
      ObjectSetInteger(0, nz, OBJPROP_BACK, true);
      ObjectSetInteger(0, nz, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nz, OBJPROP_HIDDEN, true);
   }
   ObjectSetString(0, nz, OBJPROP_TOOLTIP, ObjectGetString(0, nv, OBJPROP_TOOLTIP));
}

void LoadNewsHistory() {
   if(!g_draw || !InpShowNewsHistory || MQLInfoInteger(MQL_TESTER)) return;
   datetime now = ServerNow();
   if(g_newsviz_loaded != 0 && now - g_newsviz_loaded < 3600) return;
   g_newsviz_loaded = now;

   datetime from = iTime(_Symbol, InpZ_Timeframe, InpBarZBars);
   if(from == 0) from = now - (datetime)(PeriodSeconds(InpZ_Timeframe) * InpBarZBars);
   MqlCalendarValue vals[];
   if(!CalendarValueHistory(vals, from, now + (datetime)DAY_SEC, NULL, InpNewsCurrency)) {
      PrintFormat("⚠️ โหลดปฏิทินข่าวย้อนหลังไม่สำเร็จ (error %d)", GetLastError());
      return;
   }
   for(int i = 0; i < ArraySize(vals); i++) {
      MqlCalendarEvent ev;
      if(!CalendarEventById(vals[i].event_id, ev)) continue;
      bool high = (ev.importance == CALENDAR_IMPORTANCE_HIGH);
      bool med  = (ev.importance == CALENDAR_IMPORTANCE_MODERATE);
      if(!high && !(InpNewsIncludeMedium && med)) continue;
      string detail = StringFormat("📰 %s %s [%s] %s", TimeToString(vals[i].time, TIME_DATE|TIME_MINUTES),
                                   InpNewsCurrency, (high ? "High" : "Medium"), ev.name);
      DrawNewsEvent(vals[i].time, ev.name, detail);
   }

   // ลบข่าวที่เก่ากว่าช่วงที่แสดง
   int n = ArraySize(g_newsviz_names), w = 0;
   for(int i = 0; i + 1 < n; i += 2) {
      datetime tt = (datetime)ObjectGetInteger(0, g_newsviz_names[i], OBJPROP_TIME);
      if(tt != 0 && tt < from) {
         ObjectDelete(0, g_newsviz_names[i]);
         ObjectDelete(0, g_newsviz_names[i + 1]);
         continue;
      }
      g_newsviz_names[w++] = g_newsviz_names[i];
      g_newsviz_names[w++] = g_newsviz_names[i + 1];
   }
   if(w != n) ArrayResize(g_newsviz_names, w);
}

//====================================================================
// 🎨 DISPLAY
//====================================================================
void MoveHLine(string name, double price, color clr, ENUM_LINE_STYLE style, int width, string tip, double &cache) {
   if(MathAbs(price - cache) < _Point && ObjectFind(0, name) >= 0) return;
   cache = price;
   if(ObjectFind(0, name) < 0) {
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_STYLE, style);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
   ObjectSetDouble(0, name, OBJPROP_PRICE, ND(price));
   ObjectSetString(0, name, OBJPROP_TOOLTIP, tip);
}

// สีป้าย Z ตามโซน: ถึง T1 (ทั้งคู่) = แดงส้ม/ฟ้า, ใกล้เกณฑ์ = ทอง, ปกติ = เงิน
color LiveZColor(double z) {
   if(z > InpT1_Z)                     return InpClrLiveSell;
   if(z < -InpT1_Z)                    return InpClrLiveBuy;
   if(z >= InpT1_Z - NEAR_ZONE ||
      z <= -InpT1_Z + NEAR_ZONE)       return InpClrLiveNear;
   return InpClrLiveNormal;
}

// ป้ายค่า Z สด: ติดขอบขวาของกราฟ ที่ความสูงเดียวกับราคา Bid (มองเห็นเสมอ ไม่ต้องเปิด Chart shift)
// อัปเดตเฉพาะเมื่อข้อความ/ตำแหน่งเปลี่ยน
void UpdateLiveZLabel(double bid) {
   if(!g_draw || !InpShowLiveZ) return;
   if(!g_z_valid) {
      if(ObjectFind(0, LABEL_LIVE_Z) >= 0) ObjectDelete(0, LABEL_LIVE_Z);
      g_live_z_text = "";
      return;
   }

   string text = StringFormat("R %+.2f | S %+.2f ▶", g_z_reg, g_z_sma);
   long now_msc = MathMax(g_last_tick_msc, (long)ServerNow() * 1000);
   if(g_wsell.active)      text = "SELL " + WatchShortText(g_wsell, now_msc) + "  |  " + text;
   else if(g_wbuy.active)  text = "BUY "  + WatchShortText(g_wbuy,  now_msc) + "  |  " + text;

   int x = 0, y = 0;
   if(!ChartTimePriceToXY(0, 0, iTime(_Symbol, PERIOD_CURRENT, 0), bid, x, y)) return;
   int h = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   if(y < 8)     y = 8;          // ราคาหลุดขอบบน/ล่าง → ติดขอบไว้ให้ยังเห็น
   if(y > h - 8) y = h - 8;

   if(text == g_live_z_text && y == g_live_z_y && ObjectFind(0, LABEL_LIVE_Z) >= 0) return;

   if(ObjectFind(0, LABEL_LIVE_Z) < 0) {
      ObjectCreate(0, LABEL_LIVE_Z, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, LABEL_LIVE_Z, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, LABEL_LIVE_Z, OBJPROP_ANCHOR, ANCHOR_RIGHT);
      ObjectSetString(0,  LABEL_LIVE_Z, OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(0, LABEL_LIVE_Z, OBJPROP_FONTSIZE, InpLiveZFontSize);
      ObjectSetInteger(0, LABEL_LIVE_Z, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, LABEL_LIVE_Z, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, LABEL_LIVE_Z, OBJPROP_BACK, false);
   }
   ObjectSetInteger(0, LABEL_LIVE_Z, OBJPROP_XDISTANCE, MathMax(0, InpLiveZOffsetPx));
   ObjectSetInteger(0, LABEL_LIVE_Z, OBJPROP_YDISTANCE, y);
   ObjectSetString(0,  LABEL_LIVE_Z, OBJPROP_TEXT, text);
   ObjectSetInteger(0, LABEL_LIVE_Z, OBJPROP_COLOR, LiveZColor(g_z));
   ObjectSetString(0,  LABEL_LIVE_Z, OBJPROP_TOOLTIP,
                   StringFormat("Z_reg %+.3f (กลาง %s) | Z_SMA %+.3f (SMA20 %s) | T1 ทั้งคู่ > %.2f / T2 ทั้งคู่ > %.2f / T3 ตัวใดก็ได้ > %.2f",
                                g_z_reg, DoubleToString(g_center, _Digits), g_z_sma, DoubleToString(g_sma_mean, _Digits),
                                InpT1_Z, InpT2_Z, InpT3_Z));

   g_live_z_text = text;
   g_live_z_y    = y;
}

void UpdateZLines() {
   if(!g_draw || !g_z_valid) return;
   if(InpShowZLines) {
      MoveHLine(LINE_MAIN, g_center,                    InpClrZCenter,   STYLE_DOT,  1, "[Regression] เส้นกลาง Z = 0", g_line_main);
      MoveHLine(LINE_SELL, g_center + InpT1_Z * g_sigma, InpClrZSellLine, STYLE_DASH, 1, StringFormat("[Regression] SELL T1 Z > +%.2f", InpT1_Z), g_line_sell);
      MoveHLine(LINE_BUY,  g_center - InpT1_Z * g_sigma, InpClrZBuyLine,  STYLE_DASH, 1, StringFormat("[Regression] BUY T1 Z < −%.2f", InpT1_Z),  g_line_buy);
   }
   if(InpShowSmaZLines) {
      MoveHLine(LINE_SMA_MAIN, g_sma_mean,                     InpClrSmaCenter,   STYLE_DOT,     1, "[SMA20] เส้นกลาง Z = 0", g_line_sma_main);
      MoveHLine(LINE_SMA_SELL, g_sma_mean + InpT1_Z * g_sma_sd, InpClrSmaSellLine, STYLE_DASHDOT, 1, StringFormat("[SMA20] SELL T1 Z > +%.2f", InpT1_Z), g_line_sma_sell);
      MoveHLine(LINE_SMA_BUY,  g_sma_mean - InpT1_Z * g_sma_sd, InpClrSmaBuyLine,  STYLE_DASHDOT, 1, StringFormat("[SMA20] BUY T1 Z < −%.2f", InpT1_Z),  g_line_sma_buy);
   }
}

string WatchShortText(const WatchState &w, long now_msc) {
   double left = (double)(WatchDeadline(w) - now_msc) / 1000.0;
   if(left < 0.0) left = 0.0;
   return StringFormat("เฝ้า %s ยิงใน %.1f วิ", StageTag(w.tier), left);
}

string WatchText(const WatchState &w, bool is_sell, long now_msc) {
   datetime t   = (datetime)(now_msc / 1000);
   string   sg  = is_sell ? "+" : "−";
   if(OurPositionsTotal() > 0) return "⏸️ มีไม้ถืออยู่ (ครั้งละ 1 ไม้)";
   if(CoolActive(g_cool, t))   return StringFormat("❄️ Cool down อีก %s", FormatDuration((long)(g_cool.until - t)));
   string blk = TimeBlockReason(t);
   if(blk != "")               return "⏳ ห้ามเฝ้า: " + blk;
   if(w.active) {
      double left = (double)(WatchDeadline(w) - now_msc) / 1000.0;
      if(left < 0.0) left = 0.0;
      string need = (w.tier >= 3) ? StringFormat("Z ตัวใด > %s%.2f, ยิงทันที", sg, InpT3_Z)
                                  : StringFormat("Z ทั้งคู่ > %s%.2f, รอ %d วิ", sg, TierZ(w.tier), (w.tier == 2 ? InpT2_Sec : InpT1_Sec));
      return StringFormat("👀 เฝ้า %s (%s, Lot %.2f) | สุดขั้ว R %+.2f / S %+.2f | ไม่มีค่าใหม่มา %.1f วิ → ยิงในอีก %.1f วิ",
                          StageTag(w.tier), need, TierLot(w.tier), w.ext_r, w.ext_s, (double)(now_msc - w.last_new) / 1000.0, left);
   }
   return StringFormat("✅ รอ T1 ทั้งคู่ > %s%.2f / T2 ทั้งคู่ > %s%.2f / T3 ตัวใดก็ได้ > %s%.2f", sg, InpT1_Z, sg, InpT2_Z, sg, InpT3_Z);
}

string CoolText(datetime now) {
   if(InpCoolT2_SL <= 0 && InpCoolT3_SL <= 0) return "ปิด";
   string s = StringFormat("ชน SL ของ T2 %d / %d | T3 %d / %d", g_cool.t2, InpCoolT2_SL, g_cool.t3, InpCoolT3_SL);
   if(CoolActive(g_cool, now))
      s += StringFormat(" | ❄️ พักถึง %s (อีก %s)", TimeToString(g_cool.until, TIME_DATE|TIME_MINUTES), FormatDuration((long)(g_cool.until - now)));
   return s;
}

string PositionLines(double bid, double ask, datetime now) {
   string out = "";
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsOurPosition()) continue;
      bool     is_buy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double   open   = PositionGetDouble(POSITION_PRICE_OPEN);
      double   sl     = PositionGetDouble(POSITION_SL);
      datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
      double   prof   = is_buy ? PriceToPts(bid - open) : PriceToPts(open - ask);
      double   locked = (sl > 0.0) ? (is_buy ? PriceToPts(sl - open) : PriceToPts(open - sl)) : 0.0;

      string st;
      if(IsActivated(ticket))
         st = StringFormat("🔥 ไล่จี้ ล็อก %+.0f", locked);
      else {
         if(InpQuickWindow_Sec > 0) {
            long left = (long)InpQuickWindow_Sec - (long)(now - opened);
            if(left < 0) left = 0;
            st = StringFormat("⏱️ เหลือ %d วิ ต้องกำไรถึง %.0f", (int)left, InpTrailStart_Pts);
         }
         else
            st = StringFormat("รอกำไรถึง %.0f", InpTrailStart_Pts);
         double peak = PriceToPts(PeakOf(ticket));
         if(InpGiveback_Pct > 0.0)
            st += (peak >= InpGivebackMinPeak_Pts)
                  ? StringFormat(" | สูงสุด %.0f → ตัดถ้าเหลือ ≤ %.0f", peak, peak * (1.0 - InpGiveback_Pct / 100.0))
                  : StringFormat(" | สูงสุด %.0f", peak);
      }

      out += StringFormat("\n  #%I64u %s %.2f @ %s | กำไร %+.0f จุด | SL %s | %s",
                          ticket, (is_buy ? "BUY" : "SELL"), PositionGetDouble(POSITION_VOLUME),
                          DoubleToString(open, _Digits), prof, DoubleToString(sl, _Digits), st);
   }
   return out;
}

void UpdateDashboard(int ts, datetime now) {
   if(!g_draw || !InpShowDashboard) return;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   int buys, sells;
   CountPositions(buys, sells);

   string z_str = g_z_valid
      ? StringFormat("Z_reg %+.2f (กลาง %s, σ %.0f จุด%s)  |  Z_SMA %+.2f (SMA20 %s, σ %.0f จุด) | ต่าง %+.2f",
                     g_z_reg, DoubleToString(g_center, _Digits), PriceToPts(g_sigma), (g_sigma_floor ? " พื้น" : ""),
                     g_z_sma, DoubleToString(g_sma_mean, _Digits), PriceToPts(g_sma_sd), g_z_reg - g_z_sma)
      : "รอข้อมูลแท่งเทียน...";
   string news_str = NextNewsText(now);

   long   now_msc = MathMax(g_last_tick_msc, (long)now * 1000);
   string msg = StringFormat("=== 📊 7-Lines Counter EA v12.20 (T1 Z>%.1f %d วิ / T2 Z>%.1f %d วิ / T3 Z>%.1f ทันที | SL ไส้ ± %.0f / T3 ± %.0f | คืนกำไร %.0f%%) ===\n",
                             InpT1_Z, InpT1_Sec, InpT2_Z, InpT2_Sec, InpT3_Z, InpSLBeyond_Pts, InpSLBeyondT3_Pts, InpGiveback_Pct);
   msg += StringFormat("Z (%s, %d) : %s\n", EnumToString(InpZ_Timeframe), InpZ_Period, z_str);
   msg += StringFormat("Z แท่งที่เพิ่งปิด : R %+.2f / S %+.2f%s\n", g_prev_close_zr, g_prev_close_zs, (news_str == "" ? "" : " | " + news_str));
   msg += "SELL : " + WatchText(g_wsell, true,  now_msc) + "\n";
   msg += "BUY  : " + WatchText(g_wbuy,  false, now_msc) + "\n";
   msg += StringFormat("ออเดอร์ : BUY %d / SELL %d | สเปรด %.0f / %.0f จุด\n",
                       buys, sells, PriceToPts(ask - bid), InpMaxSpread_Pts);
   msg += "Cool down : " + CoolText(now) + "\n";
   msg += "เวลาตลาด : " + TimeStateText(ts, now) + "\n";
   if(InpShow7Lines) msg += "เส้น 7 เส้น : " + g_lines_status + "\n";
   msg += "สถานะล่าสุด : " + g_last_status;
   if(InpShowReplay) msg += "\n" + ReplayStatsText();
   msg += PositionLines(bid, ask, now);

   if(msg != g_last_comment) {
      g_last_comment = msg;
      Comment(msg);
   }
}

//====================================================================
// 🚀 EVENT HANDLERS
//====================================================================
int OnInit() {
   if(InpZ_Period < 2 || InpFastPeriod < 2) { Print("❌ Period ต้องอย่างน้อย 2"); return(INIT_PARAMETERS_INCORRECT); }
   if(InpLinesBars < 10 || InpLinesBars > 2000) { Print("❌ InpLinesBars ต้องอยู่ระหว่าง 10-2000"); return(INIT_PARAMETERS_INCORRECT); }
   if(InpBarZBars < 1 || InpBarZBars > 20000) { Print("❌ InpBarZBars ต้องอยู่ระหว่าง 1-20000"); return(INIT_PARAMETERS_INCORRECT); }
   if(InpReplayDays < 1 || InpReplayDays > 60) { Print("❌ InpReplayDays ต้องอยู่ระหว่าง 1-60"); return(INIT_PARAMETERS_INCORRECT); }
   if(InpT1_Z <= 0.0 || InpT2_Z < InpT1_Z || InpT3_Z < InpT2_Z ||
      InpT1_Sec < 0 || InpT2_Sec < 0 || InpNoNewExtEps < 0.0 || InpTierLotStep < 0.0) {
      Print("❌ ค่า Z ระดับวิกฤต (ต้อง T1 ≤ T2 ≤ T3) / เวลาเฝ้า / Lot ต่อระดับ ไม่ถูกต้อง");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpLot <= 0.0) { Print("❌ Lot ไม่ถูกต้อง"); return(INIT_PARAMETERS_INCORRECT); }
   if(InpTP_Pts <= 0.0 || InpSLBeyond_Pts < 0.0 || InpSLBeyondT3_Pts < 0.0 || InpTrailDist_Pts <= 0.0 || InpTrailInterval_Sec < 1) {
      Print("❌ TP / SL / ระยะโล่ / รอบไล่จี้ ไม่ถูกต้อง");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpQuickWindow_Sec < 0 || InpGiveback_Pct < 0.0 || InpGiveback_Pct >= 100.0 || InpGivebackMinPeak_Pts < 0.0) {
      Print("❌ เวลาตัดจบ / กฎคืนกำไร ไม่ถูกต้อง (คืนกำไร 0-99%, ระยะต้องไม่ติดลบ)");
      return(INIT_PARAMETERS_INCORRECT);
   }
   long per = PeriodSeconds(InpZ_Timeframe);
   if(InpSigmaFloorMult < 0.0 || InpBarStartDelay_Sec < 0 || InpBarEndBlock_Sec < 0 ||
      InpBarStartDelay_Sec + InpBarEndBlock_Sec >= per || InpCoolT2_SL < 0 || InpCoolT3_SL < 0 || InpCooldown_Min < 1 || InpNewsBlock_Min < 0) {
      Print("❌ ค่าพื้นตัวหาร / เวลาต้น-ท้ายแท่ง / Cool down / ช่วงข่าว ไม่ถูกต้อง");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING) {
      Print("❌ EA นี้ต้องใช้บัญชีแบบ Hedging (บัญชี Netting จะรวมไม้เป็นโพซิชันเดียว)");
      return(INIT_FAILED);
   }

   g_pmult = (_Digits == 2 || _Digits == 4) ? 0.1 : 1.0;
   g_draw  = !(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE));

   trade.SetExpertMagicNumber((ulong)InpMagic);
   trade.SetDeviationInPoints((ulong)MathMax(0.0, PtsToPrice(InpSlippage_Pts) / _Point));
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.LogLevel(LOG_LEVEL_ERRORS);

   g_session_ok = BuildWeekBlocks();
   if(!g_session_ok) Print("⚠️ อ่านเวลา Session ของ Symbol ไม่ได้ — ปิดการกรองเวลาตลาด");

   if(InpNewsFilter && MQLInfoInteger(MQL_TESTER)) Print("ℹ️ ปฏิทินข่าวใช้ไม่ได้ใน Strategy Tester — ไม่กรองช่วงข่าว");
   if(StringFind(_Symbol, "XAU") < 0) PrintFormat("⚠️ EA ออกแบบสำหรับ XAUUSD แต่กำลังรันบน %s", _Symbol);
   if(InpShow7Lines && Period() != InpZ_Timeframe)
      PrintFormat("ℹ️ กราฟเป็น %s แต่ Z ใช้ %s — เส้น 7 เส้นจะคำนวณตาม TF ของกราฟ", EnumToString(Period()), EnumToString(InpZ_Timeframe));
   InitALMAWeights(InpFastPeriod);
   g_line_clr[0] = InpClrMain; g_line_clr[1] = InpClrL1; g_line_clr[2] = InpClrL2; g_line_clr[3] = InpClrL3;
   g_line_clr[4] = InpClrL4;   g_line_clr[5] = InpClrL5; g_line_clr[6] = InpClrL6;
   g_barz_bar = 0;
   ArrayResize(g_zl_names, 0);
   ArrayResize(g_zl_times, 0);
   g_lines_total = 0;
   g_lines_bar   = 0;

   WatchReset(g_wsell);
   WatchReset(g_wbuy);
   g_bar_changed   = false;
   g_last_tick_msc = 0;
   g_zc.ok         = false;
   ReplayReset();
   g_zbar_time      = 0;
   g_z_ready        = false;
   g_blk_valid      = false;
   g_last_trail     = 0;
   g_next_try       = 0;
   g_news_loaded    = 0;
   g_news_ok        = false;
   g_prev_close_zr  = 0.0;
   g_prev_close_zs  = 0.0;
   ArrayResize(g_seg_times, 0);
   ArrayResize(g_marks, 0);
   g_marks_bar = 0;
   g_newsviz_loaded = 0;
   ArrayResize(g_newsviz_names, 0);
   ArrayResize(g_news_times, 0);
   ArrayResize(g_news_names, 0);
   g_last_comment   = "";
   g_line_main = g_line_sell = g_line_buy = 0.0;
   g_line_sma_main = g_line_sma_sell = g_line_sma_buy = 0.0;
   g_live_z_text = ""; g_live_z_y = -1;
   g_lines_status = "ยังไม่ได้วาด";
   ArrayResize(g_activated, 0);
   ArrayResize(g_peak_tk, 0);
   ArrayResize(g_peak_px, 0);
   g_gb_retry = 0;

   RefreshNews(ServerNow());
   RestoreCoolFromHistory();   // ตัวนับ SL ของ T2 / T3 / เวลาพัก ไม่หายเมื่อรีสตาร์ท

   ObjectsDeleteAll(0, OBJ_PREFIX);
   if(g_draw && InpShow7Lines) RebuildLines();   // ถ้าประวัติยังโหลดไม่ครบ จะลองใหม่ใน OnTimer
   LoadEntryMarksFromHistory();

   EventSetTimer(1);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
   EventKillTimer();
   ObjectsDeleteAll(0, OBJ_PREFIX);
   Comment("");
}

void OnTick() {
   MqlTick tk;
   if(!SymbolInfoTick(_Symbol, tk) || tk.bid <= 0.0 || tk.ask <= 0.0) return;
   g_last_tick_msc = (long)tk.time_msc;
   if(!UpdateZ(tk.bid)) return;

   UpdateLiveZLabel(tk.bid);

   int ts = GetTimeState(ServerNow());
   if(ts == TS_CLOSING) {
      CloseAllPositions();
      return;
   }
   GivebackStep(tk.bid, tk.ask);   // กฎคืนกำไรเช็คทุก Tick (เหมือน Tick Replay)
   LiveSignalStep(g_last_tick_msc, ts, tk.bid, tk.ask, true);
}

void OnTimer() {
   datetime now = ServerNow();
   int ts = GetTimeState(now);
   RefreshNews(now);

   // 1. บังคับปิดก่อนตลาดปิดสัปดาห์ / จัดการไม้ (เปิดไล่จี้, ตัดจบตามเวลา, ขยับโล่)
   if(ts == TS_CLOSING)     CloseAllPositions();
   else if(ts != TS_CLOSED) ManagePositions(now);

   // 2. ยิงเมื่อครบเวลาเฝ้า แม้ไม่มี Tick เข้า (ราคา/Z ยังเป็นค่าล่าสุด)
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   bool   zok = (bid > 0.0 && ask > 0.0 && UpdateZ(bid));
   if(zok && ts != TS_CLOSING) LiveSignalStep(MathMax(g_last_tick_msc, (long)now * 1000), ts, bid, ask, false);

   // 3. อัปเดตการแสดงผล
   if(g_draw) {
      UpdateZLines();
      UpdateLinesLive();
      UpdateBarZLabels();
      UpdateEntryMarks();
      ReplayStep();
      LoadNewsHistory();
      if(bid > 0.0) UpdateLiveZLabel(bid);
      UpdateDashboard(ts, now);
      ChartRedraw(0);   // ให้วัตถุแสดงผลแม้ช่วงที่ไม่มี Tick เข้า
   }
}

// เลื่อน/ซูม/ย่อขยายกราฟ → จัดตำแหน่งป้าย Z สดใหม่ทันที
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
   if(id != CHARTEVENT_CHART_CHANGE || !g_draw) return;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(bid > 0.0) {
      g_live_z_y = -1;
      UpdateLiveZLabel(bid);
      ChartRedraw(0);
   }
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result) {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal == 0) return;
   if(!HistoryDealSelect(trans.deal)) return;
   AddEntryMarkFromDeal(trans.deal);
   long     pos;
   bool     sl_loss;
   datetime t;
   if(!HistoryDealSelect(trans.deal) || !OutDealInfo(trans.deal, pos, sl_loss, t)) return;
   CoolApply(TierOfPosition(pos), sl_loss, t, true);   // ไม้ปิด → นับ SL ของ T2 / T3 / เริ่ม Cool down
}
//+------------------------------------------------------------------+
