//+------------------------------------------------------------------+
//|                                          Seven_Lines_Wall_EA.mq5 |
//|      Point-A Wall EA for XAUUSD (สวนจุด A ที่มีกำแพงขวาง, hit&run)   |
//+------------------------------------------------------------------+
//
// 🎯 นิยามระบบ
//  จุด A = Z_reg หรือ Z_SMA ตัวใดตัวหนึ่ง > 2.0 = ตลาดตื่น → ราคาพุ่งเข้าหา "กำแพง" (ระดับที่ตลาดเห็นร่วมกัน)
//  กำแพงขวาง = สวนแบบ hit&run (SL แคบหลังกำแพง, TP 1R, ตัดเวลา 5 นาที) / กำแพงพัง = ตามแรง
//  (แยกจาก Seven_Lines_Counter_EA — ประวัติการเปลี่ยนแปลงอยู่ใน README.md)
//
// 📐 Z (TF ของ Z, 20 แท่ง, รวมแท่งปัจจุบันที่ราคา Bid): Z_reg / Z_SMA เหมือน Counter EA, σ = SD20, Z* = Z_SMA แบบไม่มีเพดาน
// 📍 จุด A (แยกฝั่งขึ้น / ลง): เริ่มเมื่อ Z ตัวใดตัวหนึ่ง > 2.0, จบเมื่อ Z ทั้งคู่ < 1.0 หรือไม่มี Z > 2.0 ครบ 60 นาที
//
// 🧱 กำแพง (สร้างใหม่ทุกแท่ง จากแท่งที่ปิดแล้วเท่านั้น — Tick Replay ไม่มองอนาคต)
//  • W1 ยอดของจุด A ในอดีต: High / Low ของแท่งที่ Z ตรงนั้น > 2.0 (5 วัน)
//  • W2 High / Low ของวันก่อน + ช่วง Asia / London ล่าสุดที่จบแล้ว (เวลาเซิร์ฟเวอร์)
//  • W3 ตัวเลขกลมทุก $10 (± 5 ขั้นจากราคาเปิดแท่ง)
//  • W4 Swing High / Low ของ H1 (fractal 2 แท่งซ้าย-ขวา, 3 วัน)
//  • W5 ราคาที่ tick หนาแน่น: volume profile 24 ชม. จาก tick volume ของแท่ง → 5 ยอดสูงสุด
//  • W6 กำแพงสถิติ: ราคาที่ทำให้ Z* = ±6 / ±8 (ค่าเฉลี่ย / SD ของ 19 แท่งก่อน)
//  • คะแนน = จำนวนแท่งที่แตะแล้วไม่ทะลุ (3 วัน) + จำนวนกำแพงอื่นในระยะ 500 จุด
//
// 📋 วิธีเข้า (ฝั่งขึ้น: กำแพงข้างบน, ฝั่งลงกลับทิศ) — เปิด/ปิดด้วยปุ่ม, แต่ละวิธีถือได้ครั้งละ 1 ไม้ / เข้าได้ 1 ครั้งต่อจุด A
//  • H1 Limit รอที่กำแพงถัดไป (ห่างไม่เกิน 1.5σ) → ราคาแตะ = SELL, SL = กำแพง + 500
//  • H2 แตะกำแพง (± 200 จุด) แล้วถอย 0.1σ → SELL, SL = ยอดหลังแตะ + 500
//  • H3 ทะลุกำแพงเกิน 500 จุด → BUY ตามแรง, SL = กำแพง − 500
//  • hit&run: TP = 1R (R = ระยะ SL ตอนเข้า), ไม่ถึงใน 5 นาที → ปิด, ไม่มีปล่อยวิ่ง
//
// 🧪 Tick Replay: เล่นซ้ำ tick จริง → มาร์ก + สรุปแยกวิธีเข้า + CSV (กำไรสูงสุด / ต่ำสุดที่ 30 วิ / 1 / 3 / 5 นาที + ข้อมูลกำแพง)
//
#property copyright   "Commander's Quant System"
#property version     "1.00"
#property description "สวนจุด A ที่มีกำแพงขวาง (W1-W6) แบบ hit&run ด้วยวิธีเข้า H1 / H2 / H3 สำหรับ XAUUSD (บัญชี Hedging)"

#include <Trade\Trade.mqh>

//====================================================================
// 🎛️ INPUT PARAMETERS
//====================================================================
input group "=== 1. Z-Score / จุด A ==="
input ENUM_TIMEFRAMES InpZ_Timeframe       = PERIOD_M15; // Timeframe ที่ใช้คำนวณ Z
input int             InpZ_Period          = 20;         // จำนวนแท่งของ SMA / StdDev
input double          InpSigmaFloorMult    = 0.50;       // ตัวหาร Z_reg ต้องไม่น้อยกว่า ค่านี้ × StdDev ของการเปลี่ยนแปลงราคาต่อแท่ง
input double          InpA_Z               = 2.00;       // จุด A: Z_reg หรือ Z_SMA ตัวใดตัวหนึ่ง > ค่านี้
input double          InpA_EndZ            = 1.00;       // จุด A จบเมื่อ Z ทั้งคู่ (ทิศของการกระชาก) กลับต่ำกว่าค่านี้
input int             InpA_MaxIdle_Min     = 60;         // จุด A จบเมื่อไม่มี Z > จุด A ครบกี่นาที

input group "=== 2. วิธีเข้า (ค่าเริ่มต้น — สลับได้ด้วยปุ่มบนกราฟ) ==="
input bool            InpEnH1              = true;       // H1: Limit รอที่กำแพงถัดไป → สวน
input bool            InpEnH2              = true;       // H2: แตะกำแพงแล้วถอย → สวน
input bool            InpEnH3              = true;       // H3: ทะลุกำแพง → ตามแรง
input double          InpH1_MaxDist_Sigma  = 1.50;       // H1: กำแพงต้องห่างราคาไม่เกินกี่ σ
input double          InpH2_Retreat_Sigma  = 0.10;       // H2: ถอยจากยอดหลังแตะกี่ σ → สวน
input double          InpH3_Break_Pts      = 500.0;      // H3: ทะลุกำแพงเกินกี่จุด → ตามแรง (ใช้เป็นเกณฑ์ "กำแพงพัง" ของ H2 ด้วย)
input double          InpSLBeyond_Pts      = 500.0;      // SL ห่างหลังกำแพง / ยอดกี่จุด

input group "=== 3. กำแพง ==="
input bool            InpTradeW1           = true;       // W1 ยอดของจุด A ในอดีต: ใช้เทรด
input bool            InpTradeW2           = true;       // W2 High/Low วันก่อน + Asia / London: ใช้เทรด
input bool            InpTradeW3           = true;       // W3 ตัวเลขกลม: ใช้เทรด
input bool            InpTradeW4           = false;      // W4 Swing H1: ใช้เทรด
input bool            InpTradeW5           = false;      // W5 tick หนาแน่น: ใช้เทรด
input bool            InpTradeW6           = false;      // W6 กำแพงสถิติ Z*: ใช้เทรด
input bool            InpShowWalls         = true;       // แสดงกำแพงบนกราฟ
input bool            InpShowW1            = true;       // แสดง W1
input bool            InpShowW2            = true;       // แสดง W2
input bool            InpShowW3            = true;       // แสดง W3
input bool            InpShowW4            = true;       // แสดง W4
input bool            InpShowW5            = true;       // แสดง W5
input bool            InpShowW6            = true;       // แสดง W6
input int             InpW1_Days           = 5;          // W1: จำย้อนหลังกี่วัน
input int             InpAsiaStartH        = 1;          // W2: Asia เริ่มกี่โมง (เวลาเซิร์ฟเวอร์)
input int             InpAsiaEndH          = 9;          // W2: Asia จบกี่โมง
input int             InpLondonStartH      = 9;          // W2: London เริ่มกี่โมง
input int             InpLondonEndH        = 17;         // W2: London จบกี่โมง
input double          InpW3_Step           = 10.0;       // W3: ตัวเลขกลมทุกกี่ $ (ราคา)
input int             InpW4_Days           = 3;          // W4: Swing H1 ย้อนหลังกี่วัน
input int             InpW4_Fractal        = 2;          // W4: High / Low สูง / ต่ำกว่ากี่แท่ง H1 ซ้าย-ขวา
input int             InpW5_Hours          = 24;         // W5: volume profile ย้อนหลังกี่ชั่วโมง
input double          InpW5_Bin_Pts        = 500.0;      // W5: ช่องราคาของ volume profile (จุด)
input int             InpW5_Top            = 5;          // W5: เอากี่ยอด
input double          InpW6_Z1             = 6.0;        // W6: กำแพงที่ Z* = ±ค่านี้
input double          InpW6_Z2             = 8.0;        // W6: กำแพงที่ Z* = ±ค่านี้
input double          InpTouch_Pts         = 200.0;      // แตะกำแพง = ราคาห่างกำแพงไม่เกินกี่จุด
input int             InpTouchDays         = 3;          // คะแนน: นับแท่งที่แตะแล้วไม่ทะลุย้อนหลังกี่วัน
input double          InpConf_Pts          = 500.0;      // คะแนน: นับกำแพงอื่นในระยะกี่จุด

input group "=== 4. hit&run ==="
input double          InpLot               = 0.02;       // Lot
input double          InpTP_R              = 1.00;       // TP = กี่ R (R = ระยะ SL ตอนเข้า)
input int             InpTimeCut_Min       = 5;          // ไม่ถึง TP / SL ภายในกี่นาที → ปิด (0 = ปิดกฎนี้)

input group "=== 5. ออเดอร์ / ตัวกรอง ==="
input double          InpSlippage_Pts      = 300.0;      // Slippage สูงสุดตอนส่งคำสั่ง (จุด)
input long            InpMagic             = 880200;     // Magic Number (แยกจาก Counter EA)
input string          InpOrderComment      = "7L-WALL";  // คอมเมนต์ออเดอร์ (ต่อท้ายด้วยวิธีเข้า + กำแพง)
input double          InpMaxSpread_Pts     = 800.0;      // สเปรดสูงสุดที่ยอมให้เข้าไม้ (จุด)
input int             InpNoTradeAfterOpen_Min = 60;      // ห้ามเข้าไม้หลังตลาดเปิดสัปดาห์ (นาที)
input int             InpCloseBeforeClose_Min = 30;      // ปิดทุกไม้ก่อนตลาดปิดสัปดาห์ (นาที)
input bool            InpNewsFilter        = true;       // งดเข้าไม้ช่วงข่าว High (ไม้ที่ถืออยู่รันต่อ, ใช้ไม่ได้ใน Tester)
input int             InpNewsBlock_Min     = 5;          // งดก่อน / หลังเวลาข่าวออกกี่นาที
input string          InpNewsCurrency      = "USD";      // สกุลเงินของข่าว (กรอง + แสดง)

input group "=== 6. การแสดงผล ==="
input bool            InpShowDashboard     = true;       // แสดง Dashboard
input bool            InpShowZLines        = true;       // แสดงเส้นแนวนอนระดับ Z ชุด Regression (± จุด A)
input bool            InpShowSmaZLines     = true;       // แสดงเส้นแนวนอนระดับ Z ชุด SMA20 (± จุด A)
input bool            InpShowLiveZ         = true;       // แสดงป้ายค่า Z สด ณ ราคาปัจจุบัน
input int             InpLiveZFontSize     = 11;         // ขนาดตัวอักษรป้าย Z สด
input int             InpLiveZOffsetPx     = 10;         // ระยะห่างป้าย Z สดจากขอบขวาของกราฟ (พิกเซล)
input bool            InpShowBarZ          = true;       // แสดงป้ายค่า Z บนแท่งที่ถึงจุด A
input bool            InpShowFloatMark     = false;      // แสดงป้าย Z_float บนแท่งที่ราคาเปิดลอยพ้น SMA
input double          InpFloatMarkZ        = 1.00;       // ป้าย Z_float: แสดงเมื่อ Z_float > ค่านี้
input bool            InpFloatMarkLive     = false;      // ป้าย Z_float: แท่งปัจจุบันแสดงค่าเสมอ
input int             InpBarZBars          = 2000;       // จำนวนแท่งย้อนหลัง (TF ของ Z) ที่แสดงป้าย (สูงสุด 20,000)
input int             InpBarZFontSize      = 8;          // ขนาดตัวอักษรป้าย Z บนแท่ง
input double          InpBarZOffset_Pts    = 300.0;      // ระยะห่างป้ายจากไส้เทียน (จุด)
input bool            InpShowEntryMarks    = true;       // มาร์กจุดเปิดไม้จริง + ระยะห่างถึงปลายไส้เทียน
input bool            InpShowReplay        = true;       // Tick Replay: จำลองไม้ย้อนหลังจาก tick จริง + ผลแต่ละไม้
input int             InpReplayDays        = 10;         // Tick Replay: ย้อนหลังกี่วัน (1-60)
input bool            InpShowReplayBlocked = true;       // Tick Replay: มาร์กสัญญาณที่ถูกตัวกรองทิ้ง
input bool            InpReplayCSV         = true;       // Tick Replay: บันทึกไม้ + ผล + ระยะกำไรช่วงแรก ลง CSV (MQL5/Files)
input bool            InpShowNewsHistory   = true;       // แสดงช่วงข่าวบนกราฟ (ใช้ไม่ได้ใน Tester)
input bool            InpNewsIncludeMedium = false;      // แสดงข่าวระดับ Medium บนกราฟด้วย (ไม่ใช้กรอง)

input group "=== 7. สี ==="
input color           InpClrW1             = clrOrangeRed;      // W1 ยอดของจุด A ในอดีต
input color           InpClrW2             = clrGold;           // W2 วันก่อน / Asia / London
input color           InpClrW3             = clrSilver;         // W3 ตัวเลขกลม
input color           InpClrW4             = clrMediumOrchid;   // W4 Swing H1
input color           InpClrW5             = clrDodgerBlue;     // W5 tick หนาแน่น
input color           InpClrW6             = clrMediumSeaGreen; // W6 กำแพงสถิติ Z*
input color           InpClrZCenter        = clrGold;           // เส้นแนวนอน: เส้นกลาง Z = 0
input color           InpClrZSellLine      = clrOrangeRed;      // เส้นแนวนอน: จุด A ฝั่งขึ้น
input color           InpClrZBuyLine       = clrAqua;           // เส้นแนวนอน: จุด A ฝั่งลง
input color           InpClrSmaCenter      = clrDarkKhaki;      // เส้นแนวนอน SMA20: เส้นกลาง Z = 0
input color           InpClrSmaSellLine    = clrLightSalmon;    // เส้นแนวนอน SMA20: จุด A ฝั่งขึ้น
input color           InpClrSmaBuyLine     = clrPaleTurquoise;  // เส้นแนวนอน SMA20: จุด A ฝั่งลง
input color           InpClrLiveSell       = clrOrangeRed;      // ป้าย Z สด: ถึงจุด A ฝั่งขึ้น
input color           InpClrLiveBuy        = clrDeepSkyBlue;    // ป้าย Z สด: ถึงจุด A ฝั่งลง
input color           InpClrLiveNear       = clrGold;           // ป้าย Z สด: ใกล้จุด A
input color           InpClrLiveNormal     = clrSilver;         // ป้าย Z สด: ปกติ
input color           InpClrBarZSell       = clrOrangeRed;      // ป้าย Z บนแท่ง: ฝั่งขึ้น (เหนือแท่ง)
input color           InpClrBarZBuy        = clrDeepSkyBlue;    // ป้าย Z บนแท่ง: ฝั่งลง (ใต้แท่ง)
input color           InpClrBarZOther      = clrGray;           // ป้าย Z_float ที่ไม่ถึงเกณฑ์
input color           InpClrFloatMark      = clrMediumPurple;   // ป้าย Z_float
input color           InpClrEntrySell      = clrRed;            // มาร์กจุดเปิด SELL (ไม้จริง)
input color           InpClrEntryBuy       = clrLime;           // มาร์กจุดเปิด BUY (ไม้จริง)
input color           InpClrEntryGap       = clrYellow;         // เส้นประ + ตัวเลขระยะห่างถึงปลายไส้ (ไม้จริง)
input color           InpClrSimWin         = clrLimeGreen;      // มาร์กจำลอง: เส้นเข้า→ออก ไม้กำไร
input color           InpClrSimLoss        = clrTomato;         // มาร์กจำลอง: เส้นเข้า→ออก ไม้ขาดทุน
input color           InpClrSimBlocked     = clrDimGray;        // มาร์กจำลอง: สัญญาณที่ถูกตัวกรองทิ้ง
input color           InpClrNewsLine       = clrMediumPurple;   // เส้นเวลาข่าว
input color           InpClrNewsZone       = C'45,35,70';       // แถบแท่งข่าว

//====================================================================
// 🔒 INTERNAL
//====================================================================
#define TS_OPEN       0
#define TS_WAIT_OPEN  1
#define TS_CLOSING    2
#define TS_CLOSED     3

#define M_H1          0
#define M_H2          1
#define M_H3          2
#define NSYS          3      // จำนวนวิธีเข้า

#define NW            6      // ชนิดกำแพง W1-W6 (index 0-5)
#define NCP           4      // จุดวัดกำไรช่วงแรก: 30 วิ / 1 / 3 / 5 นาที

#define RX_OPEN       0
#define RX_TP         1
#define RX_SL         2
#define RX_CUT        3
#define RX_WEEK       5

const string OBJ_PREFIX     = "7LWEA_";
const string LINE_MAIN      = "7LWEA_MAIN";
const string LINE_SELL      = "7LWEA_SELL_Z";
const string LINE_BUY       = "7LWEA_BUY_Z";
const string LABEL_LIVE_Z   = "7LWEA_LIVE_Z";
const string LINE_SMA_MAIN  = "7LWEA_SMA_MAIN";
const string LINE_SMA_SELL  = "7LWEA_SMA_SELL_Z";
const string LINE_SMA_BUY   = "7LWEA_SMA_BUY_Z";
const string BTN_PREFIX     = "7LWEA_BTN_M";
const long   WEEK_SEC       = 604800;
const long   DAY_SEC        = 86400;
const long   MERGE_GAP_SEC  = 12 * 3600;
const double NEAR_ZONE      = 0.5;
int          CP_SEC[NCP]    = {30, 60, 180, 300};   // จุดวัด (วินาที)

struct WeekBlock {
   long s;
   long e;
};

struct ZCache {
   bool   ok;
   double ref, sY, sXY, sYY, sD, sDD, last_close;
   double prev_zr, prev_zs;
};

// กำแพง
struct Wall {
   double   px;
   int      type;       // 0-5 = W1-W6
   int      sub;        // W2: 1 PDH 2 PDL 3 Asia H 4 Asia L 5 London H 6 London L | W1 / W4: 1 High 2 Low | W6: ±ระดับ Z*
   datetime t;          // เวลาที่เกิด (ใช้วาด / อายุ)
   int      touches;    // แท่งที่แตะแล้วไม่ทะลุ
   int      conf;       // กำแพงอื่นในระยะ InpConf_Pts
};

// ไม้ที่เปิดอยู่ (Tick Replay = จำลอง / EA จริง = เงาของไม้จริงที่ ticket)
struct VPos {
   bool   open;
   int    sys;          // M_H1 / M_H2 / M_H3
   int    dir;          // −1 SELL / +1 BUY
   int    side;         // จุด A ฝั่งไหน (0 ขึ้น / 1 ลง)
   long   msc_in;
   double p_in, sl, sl0, tp, lot;
   double zr, zs;
   long   a_msc;
   double w_px;         // กำแพงที่ใช้
   int    w_type, w_sub, w_touch, w_conf;
   double w_age_h;
   ulong  ticket;
   int    rec;
};

// จุด A ของแต่ละฝั่ง + สถานะของวิธีเข้า
struct AEvent {
   bool   active;
   long   start_msc;
   long   hot_msc;
   bool   done[NSYS];
   bool   h1_on;        // H1: Limit รออยู่ที่กำแพง h1
   Wall   h1;
   bool   t_on;         // H2 / H3: กำลังติดตามกำแพงที่แตะ
   Wall   tw;
   double t_peak;       // ยอดหลังแตะ
};

// ไม้จำลองของ Tick Replay
struct RTrade {
   long   msc_in;
   int    sys, dir, side;
   double lot, p_in, sl0, tp, zr, zs;
   long   a_msc;
   double w_px;
   int    w_type, w_sub, w_touch, w_conf;
   double w_age_h;
   double mfe, mae;
   double pa_sum, pa_ms, pa_fav;
   long   pa_msc;
   double cp_fav[NCP], cp_adv[NCP];   // กำไรสูงสุด / ติดลบสูงสุดภายใน 30 วิ / 1 / 3 / 5 นาทีหลังเข้า (ไม่ขึ้นกับการปิดไม้)
   bool   cp_done;
   long   msc_out;
   double p_out;
   int    reason;
   double pnl, usd;
   bool   drawn_final;
};

struct RBlocked {
   long   msc;
   int    sys, dir;
   double price;
   string why;
};

CTrade    trade;
double    g_pmult        = 1.0;
bool      g_draw         = true;
bool      g_en[NSYS];
bool      g_wtrade[NW];
bool      g_wshow[NW];
color     g_wclr[NW];
color     g_sys_clr[NSYS];

datetime  g_zbar_time    = 0;
bool      g_z_ready      = false;
double    g_ref          = 0.0;
bool      g_z_valid      = false;
double    g_z            = 0.0;
double    g_z_reg        = 0.0;
double    g_center       = 0.0;
double    g_sigma        = 0.0;
double    g_sma_mean     = 0.0;
double    g_sma_sd       = 0.0;
bool      g_sigma_floor  = false;
double    g_z_sma        = 0.0;
double    g_prev_close_zr = 0.0;
double    g_prev_close_zs = 0.0;
bool      g_bar_changed  = false;

double    g_bar0_hi      = 0.0;
double    g_bar0_lo      = 0.0;
double    g_bar0_open    = 0.0;
double    g_bar0_fz      = 0.0;
double    g_bar0_fsma    = 0.0;
double    g_bar0_fsd     = 0.0;
datetime  g_news_times[];
string    g_news_names[];
datetime  g_news_loaded  = 0;
bool      g_news_ok      = false;

WeekBlock g_blocks[];
int       g_block_count  = 0;
bool      g_always_open  = false;
bool      g_session_ok   = false;
datetime  g_blk_open     = 0;
datetime  g_blk_close    = 0;
bool      g_blk_valid    = false;

long      g_last_tick_msc = 0;
string    g_last_status  = "เริ่มทำงาน";
string    g_last_comment = "";
double    g_line_main    = 0.0;
double    g_line_sell    = 0.0;
double    g_line_buy     = 0.0;
double    g_line_sma_main = 0.0;
double    g_line_sma_sell = 0.0;
double    g_line_sma_buy  = 0.0;
string    g_live_z_text  = "";
int       g_live_z_y     = -1;
string    g_lay_sig      = "";
datetime  g_wall_bar     = 0;      // EA จริง: แท่งตอนสร้างกำแพงล่าสุด

RTrade     g_rt[];
RBlocked   g_rb[];
int        g_rb_drawn     = 0;
MqlRates   g_rr[];
int        g_rp_b         = -1;
datetime   g_rp_bar_t     = 0;
ZCache     g_rp_zc;
double     g_rp_hi        = 0.0;
double     g_rp_lo        = 0.0;
double     g_rp_bid = 0.0, g_rp_ask = 0.0;
long       g_rp_msc       = 0;
bool       g_rp_have      = false;
bool       g_rp_init      = false;
bool       g_rp_caught    = false;
long       g_rp_cursor    = 0;
int        g_rp_retry     = 0;
int        g_rp_news_wait = 0;
long       g_rp_ticks     = 0;
string     g_rp_status    = "ยังไม่เริ่ม";
double     g_contract     = 100.0;
int        g_cp_from      = 0;
int        g_rp_csv_rows  = -1;
int        g_rp_csv_cp    = -1;

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

string SysTag(int s) {
   switch(s) {
      case M_H1: return "H1";
      case M_H2: return "H2";
      case M_H3: return "H3";
   }
   return "?";
}

int SysFromComment(string c) {
   for(int s = 0; s < NSYS; s++)
      if(StringFind(c, " " + SysTag(s) + " ") >= 0) return s;
   return -1;
}

// ชื่อกำแพง เช่น "W2 PDH", "W6 Z*+8"
string WallName(int type, int sub) {
   string b = "W" + IntegerToString(type + 1);
   switch(type) {
      case 0: case 3: return b + (sub == 1 ? " High" : " Low");
      case 1:
         switch(sub) {
            case 1: return b + " PDH";
            case 2: return b + " PDL";
            case 3: return b + " Asia H";
            case 4: return b + " Asia L";
            case 5: return b + " London H";
            case 6: return b + " London L";
         }
         return b;
      case 2: return b + " กลม";
      case 4: return b + " tick หนา";
      case 5: return b + StringFormat(" Z*%+d", sub);
   }
   return b;
}

//====================================================================
// 🧮 Z
//====================================================================
double EffectiveZ(double zr, double zs) {
   return (MathAbs(zr) >= MathAbs(zs)) ? zr : zs;
}
// แท่งลอยตัว (ทิศของการกระชาก): fz = (ราคาเปิด − SMA ตอนเปิดแท่ง) ÷ SD20 → SELL ใช้ +fz / BUY ใช้ −fz (> 0 = พ้นเส้น SMA)
double ZFloat(int dir, double fz) { return (dir == -1) ? fz : -fz; }
// SMA / SD20 ตอนเปิดแท่งจากแคช Z (ราคาปิด 19 แท่งก่อน + ราคาเปิด) → fz (0 = คำนวณไม่ได้)
double FloatAtOpen(const ZCache &zc, double open, double &sma, double &sd) {
   double zr, zs, fit, sig, mn, ssd;
   bool   fl;
   sma = 0.0; sd = 0.0;
   if(open <= 0.0 || !ZAtPrice(zc, open, zr, zs, fit, sig, fl, mn, ssd) || ssd <= 0.0) return 0.0;
   sma = zc.ref + mn;
   sd  = ssd;
   return (open - sma) / sd;
}
// Z* = Z_SMA แบบไม่มีเพดาน: ราคาปัจจุบันอยู่ในหน้าต่าง n ค่า → |Z_SMA| < √(n−1) เสมอ (n = 20 → 4.36) และอิ่มตัวใกล้เพดาน
//   Z* = (ราคา − ค่าเฉลี่ย n−1 แท่งก่อน) ÷ SD ของ n−1 แท่งนั้น = Z · √(n ÷ (n − 1 − Z²))  (Z 2.5 → 3.1, 3.0 → 4.2, 3.5 → 6.0, 4.0 → 10.3)
double ZStar(double z) {
   double n = (double)InpZ_Period, q = n - 1.0 - z * z;
   if(q <= 1.0e-6) return (z >= 0.0) ? 99.0 : -99.0;
   return z * MathSqrt(n / q);
}
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
   g_bar0_open = iOpen(_Symbol, InpZ_Timeframe, 0);
   g_bar0_fz   = FloatAtOpen(g_zc, g_bar0_open, g_bar0_fsma, g_bar0_fsd);

   g_zbar_time = t0;
   g_z_ready   = true;
   return true;
}
bool UpdateZ(double bid) {
   g_z_valid = false;
   if(!RefreshClosedBars()) return false;

   if(bid > g_bar0_hi)                    g_bar0_hi = bid;
   if(g_bar0_lo <= 0.0 || bid < g_bar0_lo) g_bar0_lo = bid;
   if(g_bar0_fsd <= 0.0) {   // ตอนขึ้นแท่งใหม่ยังอ่านราคาเปิดไม่ได้ → ลองใหม่ (ไม่ได้จริง ๆ ใช้ Bid แรกของแท่ง)
      if(g_bar0_open <= 0.0) g_bar0_open = iOpen(_Symbol, InpZ_Timeframe, 0);
      if(g_bar0_open <= 0.0) g_bar0_open = bid;
      g_bar0_fz = FloatAtOpen(g_zc, g_bar0_open, g_bar0_fsma, g_bar0_fsd);
   }

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
// 📰 ปฏิทินข่าว
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
// 🕒 เวลา / SESSION / ตัวกรอง
//====================================================================
// แท่ง (TF ของ Z) ที่เวลา t อยู่
datetime BarStartOf(datetime t) {
   long per = PeriodSeconds(InpZ_Timeframe);
   return (per > 0) ? (datetime)((long)t - (long)t % per) : t;
}
// ตัวกรองตอนเข้าไม้ (ใช้ร่วมกัน) — เวลาตลาด + เพดานสเปรด + ข่าว
string EntryBlockReason(int ts, double bid, double ask, datetime t) {
   if(ts != TS_OPEN) return "เวลาตลาด";
   double sp = PriceToPts(ask - bid);
   if(sp > InpMaxSpread_Pts) return StringFormat("สเปรด %.0f > %.0f จุด", sp, InpMaxSpread_Pts);
   if(NewsNear(t) >= 0) return "ช่วงข่าว";
   return "";
}
bool TradeAllowed() {
   return TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) && MQLInfoInteger(MQL_TRADE_ALLOWED);
}
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

// Z ของแท่ง j ที่ราคา price (ราคาปิด n−1 แท่งก่อนหน้า + price)
// Z ของแท่ง j ที่ราคา price (ราคาปิด n−1 แท่งก่อนหน้า + price)
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

//====================================================================
// 🧱 กำแพง W1-W6 — สร้างจากแท่ง r[0..b−1] ที่ปิดแล้ว (b = แท่งปัจจุบัน) → ใช้ร่วมกันทั้ง EA จริงและ Tick Replay
//====================================================================
void WallAdd(Wall &w[], double px, int type, int sub, datetime t) {
   if(px <= 0.0) return;
   for(int i = ArraySize(w) - 1; i >= 0; i--)   // ชนิดเดียวกันที่ราคาเกือบเท่ากัน = ซ้ำ
      if(w[i].type == type && MathAbs(w[i].px - px) < PtsToPrice(50.0)) return;
   int n = ArraySize(w);
   ArrayResize(w, n + 1, 64);
   w[n].px = px; w[n].type = type; w[n].sub = sub; w[n].t = t; w[n].touches = 0; w[n].conf = 0;
}

void BuildWalls(const MqlRates &r[], int b, Wall &w[]) {
   ArrayResize(w, 0);
   int n = InpZ_Period;
   if(b < n + 2) return;
   long     per     = PeriodSeconds(InpZ_Timeframe);
   int      per_day = (int)(DAY_SEC / MathMax(60, per));
   datetime now_t   = r[b].time;
   double   c[];
   ArrayResize(c, b + 1);
   for(int i = 0; i <= b; i++) c[i] = r[i].close;

   // W1: แท่งปิดที่ Z ที่ High / Low ถึงจุด A
   int j0 = MathMax(n - 1, b - InpW1_Days * per_day);
   for(int j = j0; j < b; j++) {
      double zr, zs;
      if(ZForBarPrice(c, j, r[j].high, zr, zs) && MathMax(zr, zs) > InpA_Z)   WallAdd(w, r[j].high, 0, 1, r[j].time);
      if(ZForBarPrice(c, j, r[j].low,  zr, zs) && MathMax(-zr, -zs) > InpA_Z) WallAdd(w, r[j].low,  0, 2, r[j].time);
   }

   // W2: วันก่อน + Asia / London ล่าสุดที่จบแล้ว (เวลาเซิร์ฟเวอร์)
   datetime today = now_t - (datetime)((long)now_t % DAY_SEC);
   int      hour  = (int)(((long)now_t % DAY_SEC) / 3600);
   datetime pday  = 0;
   for(int j = b - 1; j >= 0 && j >= b - 4 * per_day; j--) {
      datetime d = r[j].time - (datetime)((long)r[j].time % DAY_SEC);
      if(d < today) { pday = d; break; }
   }
   double pdh = 0.0, pdl = 0.0, ah = 0.0, al = 0.0, lh = 0.0, ll = 0.0;
   datetime adate = (hour >= InpAsiaEndH) ? today : pday;     // Asia ล่าสุดที่จบแล้ว
   datetime ldate = (hour >= InpLondonEndH) ? today : pday;   // London ล่าสุดที่จบแล้ว
   for(int j = b - 1; j >= 0 && j >= b - 4 * per_day; j--) {
      datetime d = r[j].time - (datetime)((long)r[j].time % DAY_SEC);
      int      h = (int)(((long)r[j].time % DAY_SEC) / 3600);
      if(d == pday) { pdh = MathMax(pdh, r[j].high); pdl = (pdl <= 0.0) ? r[j].low : MathMin(pdl, r[j].low); }
      if(d == adate && h >= InpAsiaStartH && h < InpAsiaEndH)     { ah = MathMax(ah, r[j].high); al = (al <= 0.0) ? r[j].low : MathMin(al, r[j].low); }
      if(d == ldate && h >= InpLondonStartH && h < InpLondonEndH) { lh = MathMax(lh, r[j].high); ll = (ll <= 0.0) ? r[j].low : MathMin(ll, r[j].low); }
      if(d < pday) break;
   }
   WallAdd(w, pdh, 1, 1, pday);
   WallAdd(w, pdl, 1, 2, pday);
   WallAdd(w, ah,  1, 3, adate + (datetime)(InpAsiaStartH * 3600));
   WallAdd(w, al,  1, 4, adate + (datetime)(InpAsiaStartH * 3600));
   WallAdd(w, lh,  1, 5, ldate + (datetime)(InpLondonStartH * 3600));
   WallAdd(w, ll,  1, 6, ldate + (datetime)(InpLondonStartH * 3600));

   // W3: ตัวเลขกลม ± 5 ขั้นจากราคาเปิดแท่ง
   if(InpW3_Step > 0.0) {
      double base = MathFloor(r[b].open / InpW3_Step) * InpW3_Step;
      for(int k = -4; k <= 5; k++) WallAdd(w, base + k * InpW3_Step, 2, 0, now_t);
   }

   // W4: Swing High / Low ของ H1 (รวมแท่ง TF ของ Z เป็นชั่วโมง, ยืนยันแล้วเท่านั้น)
   int      hn = 0;
   double   hh[], hl[];
   datetime ht[];
   for(int j = MathMax(0, b - InpW4_Days * per_day); j < b; j++) {
      datetime hk = r[j].time - (datetime)((long)r[j].time % 3600);
      if(hn == 0 || ht[hn - 1] != hk) {
         ArrayResize(hh, hn + 1); ArrayResize(hl, hn + 1); ArrayResize(ht, hn + 1);
         ht[hn] = hk; hh[hn] = r[j].high; hl[hn] = r[j].low; hn++;
      }
      else { hh[hn - 1] = MathMax(hh[hn - 1], r[j].high); hl[hn - 1] = MathMin(hl[hn - 1], r[j].low); }
   }
   int f = MathMax(1, InpW4_Fractal);
   for(int i = f; i < hn - f; i++) {
      if(ht[i + f] + 3600 > now_t) break;   // แท่ง H1 ทางขวายังไม่ปิด
      bool sh = true, sl = true;
      for(int q = 1; q <= f; q++) {
         if(hh[i - q] >= hh[i] || hh[i + q] >= hh[i]) sh = false;
         if(hl[i - q] <= hl[i] || hl[i + q] <= hl[i]) sl = false;
      }
      if(sh) WallAdd(w, hh[i], 3, 1, ht[i]);
      if(sl) WallAdd(w, hl[i], 3, 2, ht[i]);
   }

   // W5: volume profile จาก tick volume ของแท่ง (กระจายเท่ากันตลอดช่วง High-Low) → ยอดสูงสุด InpW5_Top ยอด
   double bin = PtsToPrice(InpW5_Bin_Pts);
   int    v0  = MathMax(0, b - (int)MathCeil(InpW5_Hours * 3600.0 / MathMax(60, per)));
   if(bin > 0.0 && v0 < b) {
      double lo = r[v0].low, hi = r[v0].high;
      for(int j = v0; j < b; j++) { lo = MathMin(lo, r[j].low); hi = MathMax(hi, r[j].high); }
      int nb = (int)MathFloor((hi - lo) / bin) + 1;
      if(nb > 0 && nb < 5000) {
         double vol[];
         ArrayResize(vol, nb);
         ArrayInitialize(vol, 0.0);
         for(int j = v0; j < b; j++) {
            int a  = (int)MathFloor((r[j].low - lo) / bin), z = (int)MathFloor((r[j].high - lo) / bin);
            double each = (double)r[j].tick_volume / (z - a + 1);
            for(int q = a; q <= z && q < nb; q++) vol[q] += each;
         }
         for(int pick = 0; pick < InpW5_Top; pick++) {   // ยอดสูงสุดที่เป็นยอดเฉพาะจุด (สูงกว่า ±2 ช่องข้างเคียง)
            int best = -1;
            for(int q = 0; q < nb; q++) {
               if(vol[q] <= 0.0) continue;
               bool peak = true;
               for(int d = -2; d <= 2 && peak; d++)
                  if(d != 0 && q + d >= 0 && q + d < nb && vol[q + d] > vol[q]) peak = false;
               if(peak && (best < 0 || vol[q] > vol[best])) best = q;
            }
            if(best < 0) break;
            WallAdd(w, lo + (best + 0.5) * bin, 4, pick + 1, r[v0].time);
            vol[best] = -1.0;   // ไม่เลือกซ้ำ
         }
      }
   }

   // W6: ราคาที่ทำให้ Z* = ±InpW6_Z1 / ±InpW6_Z2 (ค่าเฉลี่ย / SD ของ n−1 แท่งก่อน)
   double s = 0.0, ss = 0.0;
   for(int j = b - n + 1; j < b; j++) { s += r[j].close; ss += r[j].close * r[j].close; }
   double m = s / (n - 1), v = ss / (n - 1) - m * m;
   if(v > 0.0) {
      double sd = MathSqrt(v);
      WallAdd(w, m + InpW6_Z1 * sd, 5, (int)InpW6_Z1, now_t);
      WallAdd(w, m - InpW6_Z1 * sd, 5, -(int)InpW6_Z1, now_t);
      WallAdd(w, m + InpW6_Z2 * sd, 5, (int)InpW6_Z2, now_t);
      WallAdd(w, m - InpW6_Z2 * sd, 5, -(int)InpW6_Z2, now_t);
   }

   // คะแนน: แท่งที่แตะแล้วไม่ทะลุ (ราคาเปิด / ปิดอยู่ฝั่งเดียวกันของกำแพง) + กำแพงอื่นในระยะ InpConf_Pts
   double band = PtsToPrice(InpTouch_Pts), cf = PtsToPrice(InpConf_Pts);
   int    t0   = MathMax(0, b - InpTouchDays * per_day);
   for(int i = 0; i < ArraySize(w); i++) {
      double px = w[i].px;
      for(int j = t0; j < b; j++) {
         if(r[j].high < px - band || r[j].low > px + band) continue;
         if((r[j].open < px && r[j].close < px) || (r[j].open > px && r[j].close > px)) w[i].touches++;
      }
      for(int q = 0; q < ArraySize(w); q++)
         if(q != i && MathAbs(w[q].px - px) <= cf) w[i].conf++;
   }
}

//====================================================================
// ⚙️ ENGINE: จุด A + H1 / H2 / H3 + hit&run (ใช้ร่วมกันทั้ง EA จริงและ Tick Replay)
//   ฝั่ง k: 0 = จุด A ขาขึ้น (กำแพงข้างบน, สวน = SELL), 1 = ขาลง — g = +1 / −1 แปลงทุกอย่างเป็นทิศของการกระชาก
//====================================================================
class CEngine {
public:
   bool     m_live;
   long     m_now;
   AEvent   m_ev[2];
   VPos     m_pos[];
   Wall     m_walls[];

   CEngine(void) { m_live = false; Reset(); }

   void Reset(void) {
      m_now = 0;
      ArrayResize(m_pos, 0);
      ArrayResize(m_walls, 0);
      ZeroMemory(m_ev[0]);
      ZeroMemory(m_ev[1]);
   }

   virtual bool XOpen(VPos &p)                           { return false; }
   virtual bool XClose(int i, double price, int reason)  { return false; }
   virtual void XBlocked(int sys, int dir, double price, string why) {}
   virtual void XTrack(int i, double prof)               {}

   bool HasOpen(int sys) {
      for(int i = ArraySize(m_pos) - 1; i >= 0; i--)
         if(m_pos[i].open && m_pos[i].sys == sys) return true;
      return false;
   }

   int CountOpen(void) {
      int c = 0;
      for(int i = ArraySize(m_pos) - 1; i >= 0; i--) if(m_pos[i].open) c++;
      return c;
   }

   // กำแพงที่ใช้เทรดซึ่งอยู่ข้างหน้า (ทิศ g) ใกล้สุด ในระยะ ≤ max_d (ราคา), −1 = ไม่มี
   int NearestAhead(double g, double bid, double max_d) {
      int    best = -1;
      double bd   = 0.0;
      for(int i = 0; i < ArraySize(m_walls); i++) {
         if(!g_wtrade[m_walls[i].type]) continue;
         double d = g * (m_walls[i].px - bid);
         if(d < 0.0 || d > max_d) continue;
         if(best < 0 || d < bd) { best = i; bd = d; }
      }
      return best;
   }

   // กำแพงที่ใช้เทรดซึ่งราคาอยู่ในระยะแตะ (± InpTouch_Pts) ใกล้สุด, −1 = ไม่มี
   int Touching(double bid) {
      int    best = -1;
      double bd   = 0.0, band = PtsToPrice(InpTouch_Pts);
      for(int i = 0; i < ArraySize(m_walls); i++) {
         if(!g_wtrade[m_walls[i].type]) continue;
         double d = MathAbs(m_walls[i].px - bid);
         if(d > band) continue;
         if(best < 0 || d < bd) { best = i; bd = d; }
      }
      return best;
   }

   // เปิดไม้ (TP = InpTP_R × R) → true = ใช้สิทธิ์ในจุด A นี้แล้ว (เปิดได้ หรือถูกตัวกรองทิ้ง)
   bool Fire(int sys, int dir, int k, double bid, double ask, double sl, const Wall &w, string block, double zr, double zs) {
      if(!g_en[sys] || HasOpen(sys)) return false;
      double price = (dir == -1) ? bid : ask;
      if(block != "") { XBlocked(sys, dir, price, block); return true; }
      if((dir == -1 && sl <= price) || (dir == 1 && sl >= price)) return false;
      double R = MathAbs(price - sl);
      VPos p;
      ZeroMemory(p);
      p.open    = true;
      p.sys     = sys;
      p.dir     = dir;
      p.side    = k;
      p.msc_in  = m_now;
      p.p_in    = price;
      p.sl      = sl;
      p.sl0     = sl;
      p.tp      = (dir == -1) ? price - InpTP_R * R : price + InpTP_R * R;
      p.lot     = NormalizeLot(InpLot);
      p.zr      = zr;
      p.zs      = zs;
      p.a_msc   = m_ev[k].start_msc;
      p.w_px    = w.px;
      p.w_type  = w.type;
      p.w_sub   = w.sub;
      p.w_touch = w.touches;
      p.w_conf  = w.conf;
      p.w_age_h = (double)((long)(m_now / 1000) - (long)w.t) / 3600.0;
      p.rec     = -1;
      if(!XOpen(p)) return false;
      int n = ArraySize(m_pos);
      ArrayResize(m_pos, n + 1);
      m_pos[n] = p;
      return true;
   }

   // hit&run: SL / TP (Tick Replay — EA จริงโบรกปิดให้) + ตัดเวลา + ปิดก่อนปิดสัปดาห์
   void Manage(long msc, double bid, double ask, int ts) {
      for(int i = ArraySize(m_pos) - 1; i >= 0; i--) {
         if(!m_pos[i].open) continue;
         int    d    = m_pos[i].dir;
         double px   = (d == -1) ? ask : bid;
         double prof = (d == -1) ? m_pos[i].p_in - ask : bid - m_pos[i].p_in;
         XTrack(i, prof);
         if(ts == TS_CLOSING) { XClose(i, px, RX_WEEK); continue; }
         if(!m_live) {
            bool sl_hit = (d == -1) ? ask >= m_pos[i].sl : bid <= m_pos[i].sl;
            bool tp_hit = (m_pos[i].tp > 0.0) && ((d == -1) ? ask <= m_pos[i].tp : bid >= m_pos[i].tp);
            if(sl_hit) { XClose(i, px, RX_SL); continue; }
            if(tp_hit) { XClose(i, m_pos[i].tp, RX_TP); continue; }
         }
         if(InpTimeCut_Min > 0 && msc - m_pos[i].msc_in >= (long)InpTimeCut_Min * 60000) XClose(i, px, RX_CUT);
      }
      int n = ArraySize(m_pos), w = 0;
      for(int i = 0; i < n; i++) {
         if(!m_pos[i].open) continue;
         if(w != i) m_pos[w] = m_pos[i];
         w++;
      }
      if(w != n) ArrayResize(m_pos, w);
   }

   void SideStep(AEvent &e, int k, double bid, double ask, double zr, double zs, double sd, string block) {
      double g    = (k == 0) ? 1.0 : -1.0;
      int    fd   = (k == 0) ? -1 : 1;           // ทิศสวน
      double gz   = MathMax(g * zr, g * zs);
      double slb  = PtsToPrice(InpSLBeyond_Pts);
      double brk  = PtsToPrice(InpH3_Break_Pts);
      double band = PtsToPrice(InpTouch_Pts);

      // 1) เริ่ม / จบจุด A
      if(!e.active) {
         if(gz <= InpA_Z) return;
         ZeroMemory(e);
         e.active    = true;
         e.start_msc = m_now;
         e.hot_msc   = m_now;
      }
      else {
         if(gz > InpA_Z) e.hot_msc = m_now;
         if(gz < InpA_EndZ || m_now - e.hot_msc > (long)InpA_MaxIdle_Min * 60000) { ZeroMemory(e); return; }
      }

      // 2) H1: Limit ที่กำแพงข้างหน้าใกล้สุด (≤ InpH1_MaxDist_Sigma σ) — ราคาถึงกำแพง = สวน, SL = กำแพง + 500
      if(g_en[M_H1] && !e.done[M_H1]) {
         if(e.h1_on && g * (bid - e.h1.px) >= 0.0) {
            e.h1_on = false;
            if(Fire(M_H1, fd, k, bid, ask, e.h1.px + g * slb, e.h1, block, zr, zs)) e.done[M_H1] = true;
         }
         if(!e.done[M_H1]) {
            int i = NearestAhead(g, bid, InpH1_MaxDist_Sigma * sd);
            e.h1_on = (i >= 0);
            if(e.h1_on) e.h1 = m_walls[i];
         }
      }

      // 3) H2 / H3: แตะกำแพง → ติดตามยอดหลังแตะ
      if(!e.t_on) {
         int i = Touching(bid);
         if(i >= 0) { e.t_on = true; e.tw = m_walls[i]; e.t_peak = bid; }
      }
      if(!e.t_on) return;
      if(g * (bid - e.t_peak) > 0.0) e.t_peak = bid;
      bool broken = g * (e.t_peak - e.tw.px) >= brk;
      if(broken) {
         // H3: ทะลุเกิน InpH3_Break_Pts → ตามแรง, SL = กำแพง − 500
         if(g * (bid - e.tw.px) >= brk && !e.done[M_H3])
            if(Fire(M_H3, -fd, k, bid, ask, e.tw.px - g * slb, e.tw, block, zr, zs)) e.done[M_H3] = true;
         e.t_on = false;   // กำแพงนี้พังแล้ว → หาแตะกำแพงถัดไป
         return;
      }
      // H2: ถอยจากยอดหลังแตะ InpH2_Retreat_Sigma σ → สวน, SL = ยอดหลังแตะ + 500
      if(!e.done[M_H2] && g * (e.t_peak - bid) >= InpH2_Retreat_Sigma * sd)
         if(Fire(M_H2, fd, k, bid, ask, e.t_peak + g * slb, e.tw, block, zr, zs)) e.done[M_H2] = true;
      // ถอยห่างกำแพงเกิน 1σ (ไม่พัง) → เลิกติดตาม หาแตะใหม่
      if(g * (e.tw.px - bid) > MathMax(sd, band)) e.t_on = false;
   }

   void Step(long msc, double bid, double ask, const ZCache &zc, int ts, string block) {
      m_now = msc;
      Manage(msc, bid, ask, ts);
      double zr = 0.0, zs = 0.0, fit, sig, mn, sd = 0.0;
      bool   fl;
      if(!ZAtPrice(zc, bid, zr, zs, fit, sig, fl, mn, sd) || sd <= 0.0) return;
      SideStep(m_ev[0], 0, bid, ask, zr, zs, sd, block);
      SideStep(m_ev[1], 1, bid, ask, zr, zs, sd, block);
   }
};

//====================================================================
// 🧪 TICK REPLAY ENGINE (ไม้จำลอง → g_rt)
//====================================================================
void ProfitAvgAdd(int i, long msc, double fav) {
   if(msc > g_rt[i].pa_msc) {
      double dt = (double)(msc - g_rt[i].pa_msc);
      g_rt[i].pa_sum += g_rt[i].pa_fav * dt;
      g_rt[i].pa_ms  += dt;
   }
   g_rt[i].pa_msc = msc;
   g_rt[i].pa_fav = fav;
}
double ProfitAvgPts(int i) {
   return PriceToPts(g_rt[i].pa_ms > 0.0 ? g_rt[i].pa_sum / g_rt[i].pa_ms : g_rt[i].pa_fav);
}

class CReplay : public CEngine {
public:
   virtual bool XOpen(VPos &p) {
      int i = ArraySize(g_rt);
      ArrayResize(g_rt, i + 1, 256);
      ZeroMemory(g_rt[i]);
      g_rt[i].msc_in  = p.msc_in;
      g_rt[i].sys     = p.sys;
      g_rt[i].dir     = p.dir;
      g_rt[i].side    = p.side;
      g_rt[i].lot     = p.lot;
      g_rt[i].p_in    = p.p_in;
      g_rt[i].sl0     = p.sl;
      g_rt[i].tp      = p.tp;
      g_rt[i].zr      = p.zr;
      g_rt[i].zs      = p.zs;
      g_rt[i].a_msc   = p.a_msc;
      g_rt[i].w_px    = p.w_px;
      g_rt[i].w_type  = p.w_type;
      g_rt[i].w_sub   = p.w_sub;
      g_rt[i].w_touch = p.w_touch;
      g_rt[i].w_conf  = p.w_conf;
      g_rt[i].w_age_h = p.w_age_h;
      g_rt[i].pa_msc  = p.msc_in;
      g_rt[i].reason  = RX_OPEN;
      p.rec = i;
      return true;
   }

   virtual bool XClose(int i, double price, int reason) {
      int    r    = m_pos[i].rec;
      double diff = (m_pos[i].dir == -1) ? m_pos[i].p_in - price : price - m_pos[i].p_in;
      ProfitAvgAdd(r, m_now, diff);
      g_rt[r].pnl     = PriceToPts(diff);
      g_rt[r].usd     = diff * m_pos[i].lot * g_contract;
      g_rt[r].msc_out = m_now;
      g_rt[r].p_out   = price;
      g_rt[r].reason  = reason;
      m_pos[i].open   = false;
      return true;
   }

   virtual void XBlocked(int sys, int dir, double price, string why) {
      int k = ArraySize(g_rb);
      ArrayResize(g_rb, k + 1);
      g_rb[k].msc = m_now; g_rb[k].sys = sys; g_rb[k].dir = dir; g_rb[k].price = price; g_rb[k].why = why;
   }

   virtual void XTrack(int i, double prof) {
      int r = m_pos[i].rec;
      if(prof > g_rt[r].mfe) g_rt[r].mfe = prof;
      if(prof < g_rt[r].mae) g_rt[r].mae = prof;
      ProfitAvgAdd(r, m_now, prof);
   }
};

//====================================================================
// 💼 EA ENGINE (ส่งคำสั่งจริง) — SL / TP อยู่ที่โบรก, ไม้ที่โบรกปิดแล้วลบออกใน LiveSync
//====================================================================
class CLive : public CEngine {
public:
   datetime m_retry;
   datetime m_close_retry;

   CLive(void) { m_live = true; m_retry = 0; m_close_retry = 0; }

   virtual bool XOpen(VPos &p) {
      datetime now = ServerNow();
      if(now < m_retry) return false;
      if(!TradeAllowed()) { g_last_status = SysTag(p.sys) + " มีสัญญาณแต่ปิด Algo Trading อยู่"; m_retry = now + 5; return false; }
      double stops = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
      double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl    = ND((p.dir == -1) ? MathMax(p.sl, ask + stops + _Point) : MathMin(p.sl, bid - stops - _Point));
      double tp    = ND((p.dir == -1) ? MathMin(p.tp, bid - stops - _Point) : MathMax(p.tp, ask + stops + _Point));
      string cmt   = StringFormat("%s %s W%d", InpOrderComment, SysTag(p.sys), p.w_type + 1);
      bool   ok    = (p.dir == -1) ? trade.Sell(p.lot, _Symbol, bid, sl, tp, cmt) : trade.Buy(p.lot, _Symbol, ask, sl, tp, cmt);
      uint   rc    = trade.ResultRetcode();
      if(!ok || (rc != TRADE_RETCODE_DONE && rc != TRADE_RETCODE_PLACED && rc != TRADE_RETCODE_DONE_PARTIAL)) {
         m_retry = now + 1;
         g_last_status = StringFormat("%s %s ส่งคำสั่งไม่สำเร็จ: %u %s", SysTag(p.sys), (p.dir == -1 ? "SELL" : "BUY"), rc, trade.ResultRetcodeDescription());
         PrintFormat("❌ %s", g_last_status);
         return false;
      }
      p.ticket = trade.ResultOrder();
      if(trade.ResultPrice() > 0.0) p.p_in = trade.ResultPrice();
      p.sl = sl; p.sl0 = sl; p.tp = tp;
      g_last_status = StringFormat("✅ เปิด %s %s %.2f lot @ %s | กำแพง %s %s (แตะ %d, ซ้อน %d) | SL %s TP %s",
                                   SysTag(p.sys), (p.dir == -1 ? "SELL" : "BUY"), p.lot, DoubleToString(p.p_in, _Digits),
                                   WallName(p.w_type, p.w_sub), DoubleToString(p.w_px, _Digits), p.w_touch, p.w_conf,
                                   DoubleToString(sl, _Digits), DoubleToString(tp, _Digits));
      Print(g_last_status);
      return true;
   }

   virtual bool XClose(int i, double price, int reason) {
      if(!PositionSelectByTicket(m_pos[i].ticket)) { m_pos[i].open = false; return false; }
      datetime now = ServerNow();
      if(now < m_close_retry) return false;
      if(!trade.PositionClose(m_pos[i].ticket)) {
         m_close_retry = now + 1;
         PrintFormat("❌ ปิด #%I64u ไม่สำเร็จ: %u %s (จะลองใหม่)", m_pos[i].ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription());
         return false;
      }
      g_last_status = StringFormat("🛑 ปิด %s #%I64u (%s)", SysTag(m_pos[i].sys), m_pos[i].ticket, ReplayReasonName(reason));
      Print(g_last_status);
      m_pos[i].open = false;
      return true;
   }

   virtual void XBlocked(int sys, int dir, double price, string why) {
      g_last_status = StringFormat("%s %s มีสัญญาณแต่ติด: %s → ทิ้งสัญญาณ", SysTag(sys), (dir == -1 ? "SELL" : "BUY"), why);
   }
};

CReplay g_rp;
CLive   g_lv;

// EA จริง: ลบไม้ที่โบรกปิดแล้ว
void LiveSync() {
   int n = ArraySize(g_lv.m_pos), w = 0;
   for(int i = 0; i < n; i++) {
      if(!g_lv.m_pos[i].open || !PositionSelectByTicket(g_lv.m_pos[i].ticket)) continue;
      if(w != i) g_lv.m_pos[w] = g_lv.m_pos[i];
      w++;
   }
   if(w != n) ArrayResize(g_lv.m_pos, w);
}

// EA จริง: คืนไม้ที่ถืออยู่เมื่อรีสตาร์ท (วิธีเข้าจากคอมเมนต์ → ตัดเวลาต่อ, SL / TP อยู่ที่โบรก)
void LiveRestore() {
   ArrayResize(g_lv.m_pos, 0);
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsOurPosition()) continue;
      int sys = SysFromComment(PositionGetString(POSITION_COMMENT));
      if(sys < 0) continue;
      VPos p;
      ZeroMemory(p);
      p.open   = true;
      p.sys    = sys;
      p.dir    = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      p.ticket = ticket;
      p.msc_in = PositionGetInteger(POSITION_TIME_MSC);
      p.p_in   = PositionGetDouble(POSITION_PRICE_OPEN);
      p.sl     = PositionGetDouble(POSITION_SL);
      p.sl0    = p.sl;
      p.tp     = PositionGetDouble(POSITION_TP);
      p.lot    = PositionGetDouble(POSITION_VOLUME);
      p.rec    = -1;
      int n = ArraySize(g_lv.m_pos);
      ArrayResize(g_lv.m_pos, n + 1);
      g_lv.m_pos[n] = p;
   }
   if(ArraySize(g_lv.m_pos) > 0) PrintFormat("♻️ คืนไม้ที่ถืออยู่ %d ไม้", ArraySize(g_lv.m_pos));
}

//====================================================================
// 🧱 วาดกำแพง (EA จริง): เส้นจากเวลาที่เกิดถึงแท่งปัจจุบัน + ป้ายชื่อ / คะแนน
//====================================================================
string g_wall_objs[];

void DrawWalls() {
   for(int i = 0; i < ArraySize(g_wall_objs); i++) ObjectDelete(0, g_wall_objs[i]);
   ArrayResize(g_wall_objs, 0);
   if(!g_draw || !InpShowWalls) return;
   datetime now_t = CurrentZBarTime();
   datetime t_end = now_t + (datetime)(PeriodSeconds(InpZ_Timeframe) * 3);
   datetime t_min = now_t - (datetime)(InpW1_Days * DAY_SEC);
   int n = 0;
   for(int i = 0; i < ArraySize(g_lv.m_walls); i++) {
      Wall w = g_lv.m_walls[i];
      if(!g_wshow[w.type]) continue;
      datetime t0 = (w.t > t_min) ? w.t : t_min;
      if(w.type == 2 || w.type == 5) t0 = now_t;   // ตัวเลขกลม / Z*: เฉพาะแท่งปัจจุบัน
      string base = OBJ_PREFIX + "WL_" + IntegerToString(i);
      string nl = base + "_L", nt = base + "_T";
      ObjectCreate(0, nl, OBJ_TREND, 0, t0, w.px, t_end, w.px);
      ObjectSetInteger(0, nl, OBJPROP_COLOR, g_wclr[w.type]);
      ObjectSetInteger(0, nl, OBJPROP_STYLE, g_wtrade[w.type] ? STYLE_SOLID : STYLE_DOT);
      ObjectSetInteger(0, nl, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, nl, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, nl, OBJPROP_BACK, true);
      ObjectSetInteger(0, nl, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nl, OBJPROP_HIDDEN, true);
      ObjectCreate(0, nt, OBJ_TEXT, 0, t_end, w.px);
      ObjectSetString(0,  nt, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, nt, OBJPROP_FONTSIZE, 7);
      ObjectSetInteger(0, nt, OBJPROP_COLOR, g_wclr[w.type]);
      ObjectSetInteger(0, nt, OBJPROP_ANCHOR, ANCHOR_LEFT);
      ObjectSetInteger(0, nt, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nt, OBJPROP_HIDDEN, true);
      ObjectSetString(0,  nt, OBJPROP_TEXT, StringFormat(" %s ★%d", WallName(w.type, w.sub), w.touches + w.conf));
      string tip = StringFormat("%s @ %s | แตะแล้วไม่ทะลุ %d แท่ง (%d วัน) | กำแพงอื่นในระยะ %.0f จุด: %d | เกิด %s | %s",
                                WallName(w.type, w.sub), DoubleToString(w.px, _Digits), w.touches, InpTouchDays, InpConf_Pts, w.conf,
                                TimeToString(w.t, TIME_DATE|TIME_MINUTES), (g_wtrade[w.type] ? "ใช้เทรด (เส้นทึบ)" : "แสดงอย่างเดียว (เส้นจุด)"));
      ObjectSetString(0, nl, OBJPROP_TOOLTIP, tip);
      ObjectSetString(0, nt, OBJPROP_TOOLTIP, tip);
      ArrayResize(g_wall_objs, n + 2);
      g_wall_objs[n] = nl; g_wall_objs[n + 1] = nt;
      n += 2;
   }
}

// EA จริง: สร้างกำแพงใหม่ทุกแท่ง (จากแท่งที่ปิดแล้ว + ราคาเปิดของแท่งปัจจุบัน)
void LiveWallRebuild() {
   datetime t0 = CurrentZBarTime();
   if(t0 == 0 || t0 == g_wall_bar) return;
   int per_day = (int)(DAY_SEC / MathMax(60, PeriodSeconds(InpZ_Timeframe)));
   int days    = MathMax(MathMax(InpW1_Days, InpW4_Days), MathMax(InpTouchDays, 2)) + 2;
   int cnt     = days * per_day + InpZ_Period + 5;
   MqlRates r[];
   int got = CopyRates(_Symbol, InpZ_Timeframe, 0, cnt, r);
   if(got <= InpZ_Period + 3 || r[got - 1].time != t0) return;
   BuildWalls(r, got - 1, g_lv.m_walls);
   g_wall_bar = t0;
   DrawWalls();
}

//====================================================================
// 🏷️ ป้ายค่า Z บนแท่งที่ถึงจุด A (TF ของ Z)
//====================================================================
string   g_zl_names[];
datetime g_zl_times[];
datetime g_barz_bar = 0;

void RememberBarZLabel(string name, datetime t) {
   for(int i = ArraySize(g_zl_names) - 1; i >= 0; i--)
      if(g_zl_names[i] == name) return;
   int n = ArraySize(g_zl_names);
   ArrayResize(g_zl_names, n + 1);
   ArrayResize(g_zl_times, n + 1);
   g_zl_names[n] = name;
   g_zl_times[n] = t;
}

void SetBarZLabels(datetime t, double hi, double lo, const double &zr[], const double &zs[], const bool &ok[]) {
   double off = PtsToPrice(InpBarZOffset_Pts);
   string ts  = IntegerToString((long)t);
   for(int side = 0; side < 2; side++) {
      string name = OBJ_PREFIX + (side == 0 ? "ZL_S_" : "ZL_B_") + ts;
      double g    = (side == 0) ? 1.0 : -1.0;
      bool   hit_r = ok[side] && g * zr[side] > InpA_Z;
      bool   hit_s = ok[side] && g * zs[side] > InpA_Z;
      if(!(hit_r || hit_s)) { if(ObjectFind(0, name) >= 0) ObjectDelete(0, name); continue; }
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
      ObjectSetInteger(0, name, OBJPROP_COLOR, (side == 0) ? InpClrBarZSell : InpClrBarZBuy);
      ObjectSetString(0,  name, OBJPROP_TEXT, StringFormat("R%+.2f | S%+.2f | S*%+.1f", zr[side], zs[side], ZStar(zs[side])));
      ObjectSetString(0,  name, OBJPROP_TOOLTIP,
                      StringFormat("%s | ที่ %s: Z_reg %+.2f%s / Z_SMA %+.2f%s (Z* %+.2f ไม่มีเพดาน) | จุด A",
                                   TimeToString(t, TIME_DATE|TIME_MINUTES), (side == 0 ? "High" : "Low"),
                                   zr[side], (hit_r ? " ✓" : ""), zs[side], (hit_s ? " ✓" : ""), ZStar(zs[side])));
   }
}

// ป้าย Z_float ของแท่งเวลา t: ราคาเปิดลอยพ้น SMA (ตอนเปิดแท่ง) เกิน InpFloatMarkZ → SELL ป้ายใต้ Low / BUY ป้ายเหนือ High
//   always = แท่งปัจจุบัน: แสดงค่าฝั่งที่ราคาเปิดอยู่เสมอ (ไม่ถึงเกณฑ์ = สีเทา)
void SetBarFloatLabel(datetime t, double hi, double lo, double open, double sma, double sd, bool always) {
   double off = PtsToPrice(InpBarZOffset_Pts);
   string ts  = IntegerToString((long)t);
   for(int side = 0; side < 2; side++) {
      int    dir  = (side == 0) ? -1 : 1;
      string name = OBJ_PREFIX + (side == 0 ? "FL_S_" : "FL_B_") + ts;
      double zf   = (sd > 0.0) ? ZFloat(dir, (open - sma) / sd) : 0.0;
      bool   hit  = (zf > InpFloatMarkZ);
      bool   show = InpShowFloatMark && sd > 0.0 && (hit || (always && zf > 0.0));
      if(!show) { if(ObjectFind(0, name) >= 0) ObjectDelete(0, name); continue; }
      double price = (side == 0) ? (lo - off) : (hi + off);
      if(ObjectFind(0, name) < 0) {
         ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
         ObjectSetString(0,  name, OBJPROP_FONT, "Arial Bold");
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpBarZFontSize);
         ObjectSetInteger(0, name, OBJPROP_ANCHOR, (side == 0) ? ANCHOR_UPPER : ANCHOR_LOWER);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
         RememberBarZLabel(name, t);
      }
      ObjectSetInteger(0, name, OBJPROP_COLOR, hit ? InpClrFloatMark : InpClrBarZOther);
      ObjectSetInteger(0, name, OBJPROP_TIME, t);
      ObjectSetDouble(0,  name, OBJPROP_PRICE, ND(price));
      ObjectSetString(0,  name, OBJPROP_TEXT, StringFormat("F%+.2f", zf));
      ObjectSetString(0,  name, OBJPROP_TOOLTIP,
                      StringFormat("%s | ราคาเปิดลอยพ้น SMA (%s): Z_float %+.2f = (Open %s − SMA ตอนเปิดแท่ง %s) ÷ SD20 %.0f จุด",
                                   TimeToString(t, TIME_DATE|TIME_MINUTES), (side == 0 ? "ฝั่ง SELL" : "ฝั่ง BUY"), zf,
                                   DoubleToString(open, _Digits), DoubleToString(sma, _Digits), PriceToPts(sd)));
   }
}
// SMA / SD20 ของแท่ง j ที่ราคา px: ราคาปิด n−1 แท่งก่อนหน้า + px (px = ราคาเปิด → ค่าตอนเปิดแท่ง)
bool SmaSdAt(const double &c[], int j, double px, double &sma, double &sd) {
   int n = InpZ_Period;
   if(j < n - 1) return false;
   double s = px - c[j - 1], ss = s * s, ref = c[j - 1];
   for(int k = j - n + 1; k <= j - 1; k++) { double d = c[k] - ref; s += d; ss += d * d; }
   double m = s / n, v = ss / n - m * m;
   if(v <= 0.0) return false;
   sma = ref + m;
   sd  = MathSqrt(v);
   return true;
}
// ประเมินแท่งที่ปิดแล้วชุดหนึ่ง (shift เริ่มที่ from_shift จำนวน bars แท่ง)
void EvaluateClosedBars(int from_shift, int bars) {
   int n   = InpZ_Period;
   int cnt = bars + n - 1;
   double c[], h[], l[], o[];
   datetime t[];
   if(CopyClose(_Symbol, InpZ_Timeframe, from_shift, cnt, c) != cnt ||
      CopyOpen (_Symbol, InpZ_Timeframe, from_shift, cnt, o) != cnt ||
      CopyHigh (_Symbol, InpZ_Timeframe, from_shift, cnt, h) != cnt ||
      CopyLow  (_Symbol, InpZ_Timeframe, from_shift, cnt, l) != cnt ||
      CopyTime (_Symbol, InpZ_Timeframe, from_shift, cnt, t) != cnt) return;

   double zr[2], zs[2];
   bool   ok[2];
   for(int j = n - 1; j < cnt; j++) {
      double sma = 0.0, sd = 0.0;
      bool   fok = SmaSdAt(c, j, o[j], sma, sd);
      if(InpShowBarZ) {
         ok[0] = ZForBarPrice(c, j, h[j], zr[0], zs[0]);
         ok[1] = ZForBarPrice(c, j, l[j], zr[1], zs[1]);
         SetBarZLabels(t[j], h[j], l[j], zr, zs, ok);
      }
      if(fok) SetBarFloatLabel(t[j], h[j], l[j], o[j], sma, sd, false);
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
   if(!g_draw || (!InpShowBarZ && !InpShowFloatMark) || !g_z_ready) return;
   datetime t0 = CurrentZBarTime();
   if(t0 == 0) return;
   if(g_barz_bar == 0) {
      EvaluateClosedBars(1, InpBarZBars);
      g_barz_bar = t0;
   }
   else if(t0 != g_barz_bar) {
      EvaluateClosedBars(1, 1);
      PruneBarZLabels();
      g_barz_bar = t0;
   }
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
   if(InpShowBarZ) SetBarZLabels(t0, g_bar0_hi, g_bar0_lo, zr, zs, ok);
   SetBarFloatLabel(t0, g_bar0_hi, g_bar0_lo, g_bar0_open, g_bar0_fsma, g_bar0_fsd, InpFloatMarkLive);
}

//====================================================================
// 📍 มาร์กจุดเปิดไม้จริง
//====================================================================
struct EntryMark {
   ulong    deal;
   datetime t;
   double   price;
   int      dir;
   bool     closed_bar;
   string   cmt;
};
EntryMark g_marks[];
datetime  g_marks_bar = 0;

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
   int    sys     = SysFromComment(m.cmt);

   string na = OBJ_PREFIX + "EN_A_" + ds;
   if(ObjectFind(0, na) < 0) {
      ObjectCreate(0, na, is_sell ? OBJ_ARROW_SELL : OBJ_ARROW_BUY, 0, m.t, m.price);
      ObjectSetInteger(0, na, OBJPROP_COLOR, is_sell ? InpClrEntrySell : InpClrEntryBuy);
      ObjectSetInteger(0, na, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, na, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, na, OBJPROP_HIDDEN, true);
   }
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
   ObjectSetString(0, nt, OBJPROP_TEXT, StringFormat("   %s%s | %s | ห่างไส้ %.0f", (sys >= 0 ? SysTag(sys) + " " : ""), (is_sell ? "S" : "B"),
                                                    BarMinText(m.t), gap_pts));
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
// 🧪 TICK REPLAY
//====================================================================
void ReplayReset() {
   ArrayResize(g_rt, 0);
   ArrayResize(g_rb, 0);
   ArrayResize(g_rr, 0);
   g_rb_drawn = 0;
   g_rp.Reset();
   g_rp_b = -1; g_rp_bar_t = 0; g_rp_zc.ok = false; g_rp_hi = 0.0; g_rp_lo = 0.0;
   g_rp_bid = 0.0; g_rp_ask = 0.0; g_rp_msc = 0;
   g_rp_have = false; g_rp_init = false; g_rp_caught = false;
   g_rp_cursor = 0; g_rp_retry = 0; g_rp_ticks = 0; g_rp_news_wait = 0;
   g_rp_status = "ยังไม่เริ่ม";
   g_cp_from = 0;
   g_rp_csv_rows = -1;
   g_rp_csv_cp   = -1;
}

bool ReplayLoadRates() {
   int per_day = (int)(DAY_SEC / MathMax(60, PeriodSeconds(InpZ_Timeframe)));
   int days    = MathMax(MathMax(InpW1_Days, InpW4_Days), MathMax(InpTouchDays, 2)) + 4;
   int count   = (InpReplayDays + days) * per_day + InpZ_Period + 10;
   int got = CopyRates(_Symbol, InpZ_Timeframe, 0, count, g_rr);
   return (got > InpZ_Period + 3);
}

// เข้าแท่งใหม่ (TF ของ Z): สร้างแคช Z + กำแพงจากแท่งที่ปิดแล้ว
void ReplayEnterBar(int b) {
   g_rp_b = b;
   if(g_rr[b].time == g_rp_bar_t) return;
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
   BuildWalls(g_rr, b, g_rp.m_walls);
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

// กำไรสูงสุด / ติดลบสูงสุดภายใน 30 วิ / 1 / 3 / 5 นาทีหลังเข้า (ไม่ขึ้นกับการปิดไม้)
void ReplayCheckpoints(long msc, double bid, double ask) {
   int n = ArraySize(g_rt);
   for(int i = g_cp_from; i < n; i++) {
      long el = msc - g_rt[i].msc_in;
      if(!g_rt[i].cp_done && el > (long)CP_SEC[NCP - 1] * 1000) g_rt[i].cp_done = true;
      if(g_rt[i].cp_done) { if(i == g_cp_from) g_cp_from++; continue; }
      double fav = (g_rt[i].dir == -1) ? g_rt[i].p_in - ask : bid - g_rt[i].p_in;
      for(int c = 0; c < NCP; c++) {
         if(el > (long)CP_SEC[c] * 1000) continue;
         if(fav > g_rt[i].cp_fav[c])  g_rt[i].cp_fav[c] = fav;
         if(-fav > g_rt[i].cp_adv[c]) g_rt[i].cp_adv[c] = -fav;
      }
   }
}

void ReplayTick(const MqlTick &tk) {
   double bid = tk.bid, ask = tk.ask;
   if(bid <= 0.0 || ask <= 0.0) return;
   long     msc = (long)tk.time_msc;
   datetime t   = (datetime)(msc / 1000);
   if(!ReplayBarFor(t)) return;
   if(g_rp_hi <= 0.0 || bid > g_rp_hi) g_rp_hi = bid;
   if(g_rp_lo <= 0.0 || bid < g_rp_lo) g_rp_lo = bid;
   int ts = GetTimeStateAt(t);
   g_rp.Step(msc, bid, ask, g_rp_zc, ts, EntryBlockReason(ts, bid, ask, t));
   ReplayCheckpoints(msc, bid, ask);
   g_rp_bid = bid; g_rp_ask = ask; g_rp_msc = msc;
   g_rp_have = true;
   g_rp_ticks++;
}

string ReplayReasonName(int r) {
   switch(r) {
      case RX_TP:   return "TP";
      case RX_SL:   return "SL";
      case RX_CUT:  return "ตัดเวลา";
      case RX_WEEK: return "ปิดสัปดาห์";
   }
   return "ถืออยู่";
}

string ReplayReasonCode(int r) {
   switch(r) {
      case RX_TP:   return "TP";
      case RX_SL:   return "SL";
      case RX_CUT:  return "TIMECUT";
      case RX_WEEK: return "WEEKCLOSE";
   }
   return "OPEN";
}

void DrawReplayTrade(int i) {
   datetime t_in    = (datetime)(g_rt[i].msc_in / 1000);
   bool     is_sell = (g_rt[i].dir == -1);
   string   id      = IntegerToString(g_rt[i].msc_in) + "_" + IntegerToString(i);
   bool     open    = (g_rt[i].reason == RX_OPEN);
   color    clr     = g_sys_clr[g_rt[i].sys];
   string   tag     = SysTag(g_rt[i].sys);
   color    res_clr = open ? clr : ((g_rt[i].pnl > 0.0) ? InpClrSimWin : InpClrSimLoss);
   string   wn      = WallName(g_rt[i].w_type, g_rt[i].w_sub);

   string na = OBJ_PREFIX + "RP_A_" + id, nl = OBJ_PREFIX + "RP_L_" + id, nt = OBJ_PREFIX + "RP_T_" + id;
   if(ObjectFind(0, na) < 0) {
      ObjectCreate(0, na, is_sell ? OBJ_ARROW_SELL : OBJ_ARROW_BUY, 0, t_in, g_rt[i].p_in);
      ObjectSetInteger(0, na, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, na, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, na, OBJPROP_HIDDEN, true);
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
      ObjectSetInteger(0, nl, OBJPROP_COLOR, res_clr);
   }
   if(ObjectFind(0, nt) < 0) {
      ObjectCreate(0, nt, OBJ_TEXT, 0, t_in, g_rt[i].p_in);
      ObjectSetString(0,  nt, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, nt, OBJPROP_FONTSIZE, 7);
      ObjectSetInteger(0, nt, OBJPROP_ANCHOR, ANCHOR_RIGHT);
      ObjectSetInteger(0, nt, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nt, OBJPROP_HIDDEN, true);
   }
   ObjectSetInteger(0, nt, OBJPROP_COLOR, res_clr);
   ObjectSetString(0, nt, OBJPROP_TEXT,
                   open ? StringFormat("%s %s %s | %s | ถืออยู่   ", tag, (is_sell ? "S" : "B"), wn, BarMinText(t_in))
                        : StringFormat("%s %s %s | %s | %s %+.0f ($%+.2f)   ", tag, (is_sell ? "S" : "B"), wn, BarMinText(t_in),
                                       ReplayReasonName(g_rt[i].reason), g_rt[i].pnl, g_rt[i].usd));
   string tipText = StringFormat("จำลอง %s %s %.2f lot @ %s (%s) | จุด A %s เริ่ม %s (เข้าหลัง %.0f วิ)",
                                 tag, (is_sell ? "SELL" : "BUY"), g_rt[i].lot, DoubleToString(g_rt[i].p_in, _Digits),
                                 TimeToString(t_in, TIME_DATE|TIME_SECONDS), (g_rt[i].side == 1 ? "ขาลง" : "ขาขึ้น"),
                                 TimeToString((datetime)(g_rt[i].a_msc / 1000), TIME_MINUTES|TIME_SECONDS),
                                 (double)(g_rt[i].msc_in - g_rt[i].a_msc) / 1000.0);
   tipText += StringFormat("\nกำแพง %s @ %s | แตะแล้วไม่ทะลุ %d | ซ้อน %d | อายุ %.1f ชม.", wn, DoubleToString(g_rt[i].w_px, _Digits),
                           g_rt[i].w_touch, g_rt[i].w_conf, g_rt[i].w_age_h);
   tipText += StringFormat("\nZ ตอนเข้า R %+.2f / S %+.2f | SL %s / TP %s (R %.0f จุด)", g_rt[i].zr, g_rt[i].zs,
                           DoubleToString(g_rt[i].sl0, _Digits), DoubleToString(g_rt[i].tp, _Digits), PriceToPts(MathAbs(g_rt[i].p_in - g_rt[i].sl0)));
   if(!open)
      tipText += StringFormat("\nออก %s @ %s | %+.0f จุด | $%+.2f | ถือ %d วินาที | ระหว่างถือ ต่ำสุด %+.0f / สูงสุด %+.0f",
                              ReplayReasonName(g_rt[i].reason), DoubleToString(g_rt[i].p_out, _Digits), g_rt[i].pnl, g_rt[i].usd,
                              (int)((g_rt[i].msc_out - g_rt[i].msc_in) / 1000), PriceToPts(g_rt[i].mae), PriceToPts(g_rt[i].mfe));
   if(g_rt[i].cp_done)
      tipText += StringFormat("\nช่วงแรก (กำไรสูงสุด / ติดลบสูงสุด): 30 วิ %.0f / %.0f | 1 นาที %.0f / %.0f | 3 นาที %.0f / %.0f | 5 นาที %.0f / %.0f",
                              PriceToPts(g_rt[i].cp_fav[0]), PriceToPts(g_rt[i].cp_adv[0]), PriceToPts(g_rt[i].cp_fav[1]), PriceToPts(g_rt[i].cp_adv[1]),
                              PriceToPts(g_rt[i].cp_fav[2]), PriceToPts(g_rt[i].cp_adv[2]), PriceToPts(g_rt[i].cp_fav[3]), PriceToPts(g_rt[i].cp_adv[3]));
   ObjectSetString(0, na, OBJPROP_TOOLTIP, tipText);
   ObjectSetString(0, nt, OBJPROP_TOOLTIP, tipText);
   if(!open) ObjectSetString(0, nl, OBJPROP_TOOLTIP, tipText);
   g_rt[i].drawn_final = (!open && g_rt[i].cp_done);
}

void DrawReplayBlocked(int k) {
   datetime t  = (datetime)(g_rb[k].msc / 1000);
   string   nx = OBJ_PREFIX + "RP_X_" + IntegerToString(g_rb[k].msc) + "_" + IntegerToString(g_rb[k].sys);
   if(ObjectFind(0, nx) < 0) {
      ObjectCreate(0, nx, OBJ_ARROW, 0, t, g_rb[k].price);
      ObjectSetInteger(0, nx, OBJPROP_ARROWCODE, 251);   // ×
      ObjectSetInteger(0, nx, OBJPROP_COLOR, InpClrSimBlocked);
      ObjectSetInteger(0, nx, OBJPROP_ANCHOR, ANCHOR_CENTER);
      ObjectSetInteger(0, nx, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nx, OBJPROP_HIDDEN, true);
   }
   ObjectSetString(0, nx, OBJPROP_TOOLTIP,
                   StringFormat("สัญญาณ %s %s ถูกทิ้ง %s @ %s\nเหตุผล: %s", SysTag(g_rb[k].sys), (g_rb[k].dir == -1 ? "SELL" : "BUY"),
                                TimeToString(t, TIME_DATE|TIME_SECONDS), DoubleToString(g_rb[k].price, _Digits), g_rb[k].why));
}

void ReplayDraw() {
   for(int i = 0; i < ArraySize(g_rt); i++)
      if(!g_rt[i].drawn_final) DrawReplayTrade(i);
   if(InpShowReplayBlocked)
      for(; g_rb_drawn < ArraySize(g_rb); g_rb_drawn++) DrawReplayBlocked(g_rb_drawn);
}

string ReplayStatsText() {
   if(!InpShowReplay) return "";
   int    n = 0, w = 0;
   int    cnt[NSYS];
   int    win[NSYS];
   double usd = 0.0, peak = 0.0, dd = 0.0;
   double usd_s[NSYS];
   ArrayInitialize(cnt, 0); ArrayInitialize(win, 0); ArrayInitialize(usd_s, 0.0);
   for(int i = 0; i < ArraySize(g_rt); i++) {
      if(g_rt[i].reason == RX_OPEN) continue;
      int s = g_rt[i].sys;
      n++; cnt[s]++;
      if(g_rt[i].usd > 0.0) { w++; win[s]++; }
      usd += g_rt[i].usd;
      usd_s[s] += g_rt[i].usd;
      if(usd > peak) peak = usd;
      if(usd - peak < dd) dd = usd - peak;
   }
   string s = StringFormat("🧪 Replay %d วัน: %s\n   %d ไม้ | ชนะ %.0f%% | กำไรสุทธิ $%+.2f | DD $%.2f | ถูกทิ้ง %d",
                           InpReplayDays, g_rp_status, n, (n > 0 ? 100.0 * w / n : 0.0), usd, dd, ArraySize(g_rb));
   string line = "";
   for(int k = 0; k < NSYS; k++)
      line += (cnt[k] == 0) ? StringFormat("%s -  ", SysTag(k))
                            : StringFormat("%s %d ไม้ ชนะ %.0f%% $%+.2f  ", SysTag(k), cnt[k], 100.0 * win[k] / cnt[k], usd_s[k]);
   s += "\n   " + line;
   if(g_rp.CountOpen() > 0) s += StringFormat("| ถืออยู่ %d", g_rp.CountOpen());
   if(InpReplayCSV && g_rp_csv_rows >= 0)
      s += StringFormat("\n   📄 CSV: MQL5\\Files\\%s (%d ไม้)", ReplayCSVName(), g_rp_csv_rows);
   return s;
}

string ReplayCSVName() { return "7LWEA_Replay_" + _Symbol + ".csv"; }

string CsvNum(bool ok, double v, int digits) { return ok ? DoubleToString(v, digits) : ""; }

void ReplayWriteCSV(int done, int cp_done) {
   string fn = ReplayCSVName();
   int h = FileOpen(fn, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE) { PrintFormat("⚠️ เขียนไฟล์ %s ไม่สำเร็จ (error %d)", fn, GetLastError()); return; }
   FileWriteString(h, "time_in,method,side,event_side,lot,price_in,sl_pts,tp_pts,z_reg,z_sma,z_star,a_start,a_age_sec," +
                      "wall_type,wall_name,wall_price,wall_dist_pts,wall_touches,wall_conf,wall_score,wall_age_h," +
                      "fav_30s,adv_30s,fav_1m,adv_1m,fav_3m,adv_3m,fav_5m,adv_5m," +
                      "time_out,exit,hold_sec,pnl_pts,usd,profit_min_pts,profit_max_pts,profit_avg_pts\r\n");
   for(int i = 0; i < ArraySize(g_rt); i++) {
      if(g_rt[i].reason == RX_OPEN) continue;
      double zd = (g_rt[i].side == 1) ? -g_rt[i].zs : g_rt[i].zs;
      string ln = StringFormat("%s,%s,%s,%s,%.2f,%s,%.0f,%.0f,%.3f,%.3f,%.3f,%s,%.1f,",
                               TimeToString((datetime)(g_rt[i].msc_in / 1000), TIME_DATE|TIME_SECONDS), SysTag(g_rt[i].sys),
                               (g_rt[i].dir == -1 ? "SELL" : "BUY"), (g_rt[i].side == 1 ? "DOWN" : "UP"), g_rt[i].lot,
                               DoubleToString(g_rt[i].p_in, _Digits), PriceToPts(MathAbs(g_rt[i].p_in - g_rt[i].sl0)),
                               PriceToPts(MathAbs(g_rt[i].tp - g_rt[i].p_in)), g_rt[i].zr, g_rt[i].zs, ZStar(zd),
                               TimeToString((datetime)(g_rt[i].a_msc / 1000), TIME_DATE|TIME_SECONDS),
                               (double)(g_rt[i].msc_in - g_rt[i].a_msc) / 1000.0);
      ln += StringFormat("W%d,%s,%s,%.0f,%d,%d,%d,%.1f,", g_rt[i].w_type + 1, WallName(g_rt[i].w_type, g_rt[i].w_sub),
                         DoubleToString(g_rt[i].w_px, _Digits), PriceToPts(MathAbs(g_rt[i].p_in - g_rt[i].w_px)),
                         g_rt[i].w_touch, g_rt[i].w_conf, g_rt[i].w_touch + g_rt[i].w_conf, g_rt[i].w_age_h);
      bool cd = g_rt[i].cp_done;
      for(int c = 0; c < NCP; c++)
         ln += CsvNum(cd, PriceToPts(g_rt[i].cp_fav[c]), 0) + "," + CsvNum(cd, PriceToPts(g_rt[i].cp_adv[c]), 0) + ",";
      ln += StringFormat("%s,%s,%d,%.0f,%.2f,%.0f,%.0f,%.0f\r\n",
                         TimeToString((datetime)(g_rt[i].msc_out / 1000), TIME_DATE|TIME_SECONDS), ReplayReasonCode(g_rt[i].reason),
                         (int)((g_rt[i].msc_out - g_rt[i].msc_in) / 1000), g_rt[i].pnl, g_rt[i].usd,
                         PriceToPts(g_rt[i].mae), PriceToPts(g_rt[i].mfe), ProfitAvgPts(i));
      FileWriteString(h, ln);
   }
   FileClose(h);
   if(g_rp_csv_rows < 0) PrintFormat("📄 บันทึกไม้จำลอง %d ไม้ ลง MQL5\\Files\\%s (อัปเดตเมื่อมีไม้ปิดเพิ่ม)", done, fn);
   g_rp_csv_rows = done;
   g_rp_csv_cp   = cp_done;
}

void ReplayStep() {
   if(!g_draw || !InpShowReplay) return;
   if(!g_rp_init) {
      if(NewsFilterOn() && !g_news_ok && g_rp_news_wait < 60) {
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

   long chunk = g_rp_caught ? (now_msc - g_rp_cursor) : (long)DAY_SEC * 500;
   long to    = MathMin(g_rp_cursor + chunk, now_msc);
   if(to >= g_rp_cursor) {
      MqlTick ticks[];
      int got = CopyTicksRange(_Symbol, ticks, COPY_TICKS_INFO, (ulong)g_rp_cursor, (ulong)to);
      if(got < 0) { g_rp_status = StringFormat("⏳ กำลังโหลด tick (error %d)", GetLastError()); return; }
      if(got == 0 && !g_rp_caught && g_rp_retry < 3 &&
         GetTimeStateAt((datetime)((g_rp_cursor + to) / 2000)) != TS_CLOSED) {
         g_rp_retry++;
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
   if(g_rp_caught && g_rp_have) {   // เวลาผ่านไปโดยไม่มี tick (ตัดเวลา / จุด A หมดอายุ)
      datetime t  = (datetime)(now_msc / 1000);
      int      ts = GetTimeStateAt(t);
      g_rp.Step(now_msc, g_rp_bid, g_rp_ask, g_rp_zc, ts, EntryBlockReason(ts, g_rp_bid, g_rp_ask, t));
   }
   g_rp_status = g_rp_caught
                 ? StringFormat("✅ ครบแล้ว + เดินต่อแบบสด (%I64d ticks)", g_rp_ticks)
                 : StringFormat("⏳ กำลังเล่นซ้ำ ถึง %s (%I64d ticks)", TimeToString((datetime)(g_rp_cursor / 1000), TIME_DATE|TIME_MINUTES), g_rp_ticks);
   ReplayDraw();
   if(InpReplayCSV && g_rp_caught) {
      int done = 0, cp = 0;
      for(int i = 0; i < ArraySize(g_rt); i++) {
         if(g_rt[i].reason == RX_OPEN) continue;
         done++;
         if(g_rt[i].cp_done) cp++;
      }
      if(done != g_rp_csv_rows || cp != g_rp_csv_cp) ReplayWriteCSV(done, cp);
   }
}

//====================================================================
// 📰 ข่าวบนกราฟ
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
// สีป้าย Z ตามโซน: ถึงจุด A = แดงส้ม/ฟ้า, ใกล้จุด A = ทอง, ปกติ = เงิน
color LiveZColor(double z) {
   if(z > InpA_Z)                    return InpClrLiveSell;
   if(z < -InpA_Z)                   return InpClrLiveBuy;
   if(MathAbs(z) >= InpA_Z - NEAR_ZONE) return InpClrLiveNear;
   return InpClrLiveNormal;
}

void UpdateLiveZLabel(double bid) {
   if(!g_draw || !InpShowLiveZ) return;
   if(!g_z_valid) {
      if(ObjectFind(0, LABEL_LIVE_Z) >= 0) ObjectDelete(0, LABEL_LIVE_Z);
      g_live_z_text = "";
      return;
   }
   string text = StringFormat("R %+.2f | S %+.2f ▶", g_z_reg, g_z_sma);
   if(g_lv.m_ev[0].active)      text = "จุด A ขึ้น  |  " + text;
   else if(g_lv.m_ev[1].active) text = "จุด A ลง  |  " + text;
   int x = 0, y = 0;
   if(!ChartTimePriceToXY(0, 0, iTime(_Symbol, PERIOD_CURRENT, 0), bid, x, y)) return;
   int h = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   if(y < 8)     y = 8;
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
                   StringFormat("Z_reg %+.3f (กลาง %s) | Z_SMA %+.3f (SMA20 %s, Z* %+.2f) | จุด A ตัวใด > %.2f",
                                g_z_reg, DoubleToString(g_center, _Digits), g_z_sma, DoubleToString(g_sma_mean, _Digits), ZStar(g_z_sma), InpA_Z));
   g_live_z_text = text;
   g_live_z_y    = y;
}

void UpdateZLines() {
   if(!g_draw || !g_z_valid) return;
   if(InpShowZLines) {
      MoveHLine(LINE_MAIN, g_center,                   InpClrZCenter,   STYLE_DOT,  1, "[Regression] เส้นกลาง Z = 0", g_line_main);
      MoveHLine(LINE_SELL, g_center + InpA_Z * g_sigma, InpClrZSellLine, STYLE_DASH, 1, StringFormat("[Regression] จุด A ขาขึ้น Z > +%.2f", InpA_Z), g_line_sell);
      MoveHLine(LINE_BUY,  g_center - InpA_Z * g_sigma, InpClrZBuyLine,  STYLE_DASH, 1, StringFormat("[Regression] จุด A ขาลง Z < −%.2f", InpA_Z),  g_line_buy);
   }
   if(InpShowSmaZLines) {
      MoveHLine(LINE_SMA_MAIN, g_sma_mean,                    InpClrSmaCenter,   STYLE_DOT,     1, "[SMA20] เส้นกลาง Z = 0", g_line_sma_main);
      MoveHLine(LINE_SMA_SELL, g_sma_mean + InpA_Z * g_sma_sd, InpClrSmaSellLine, STYLE_DASHDOT, 1, StringFormat("[SMA20] จุด A ขาขึ้น Z > +%.2f", InpA_Z), g_line_sma_sell);
      MoveHLine(LINE_SMA_BUY,  g_sma_mean - InpA_Z * g_sma_sd, InpClrSmaBuyLine,  STYLE_DASHDOT, 1, StringFormat("[SMA20] จุด A ขาลง Z < −%.2f", InpA_Z),  g_line_sma_buy);
   }
}

// สถานะจุด A ฝั่ง k ของ EA จริง (Dashboard)
string EventText(int k, long now_msc) {
   string side = (k == 0) ? "ขาขึ้น" : "ขาลง ";
   if(!g_lv.m_ev[k].active) return "จุด A " + side + ": -";
   string s = StringFormat("จุด A %s: เริ่ม %s (%s)", side,
                           TimeToString((datetime)(g_lv.m_ev[k].start_msc / 1000), TIME_MINUTES|TIME_SECONDS),
                           FormatDuration((now_msc - g_lv.m_ev[k].start_msc) / 1000));
   if(g_lv.m_ev[k].h1_on)
      s += StringFormat(" | H1 %s Limit ที่ %s %s", (k == 0 ? "Sell" : "Buy"), WallName(g_lv.m_ev[k].h1.type, g_lv.m_ev[k].h1.sub),
                        DoubleToString(g_lv.m_ev[k].h1.px, _Digits));
   if(g_lv.m_ev[k].t_on)
      s += StringFormat(" | แตะ %s %s ยอด %s (H2 สวนเมื่อถอย %.2fσ / H3 ตามเมื่อทะลุ %.0f จุด)", WallName(g_lv.m_ev[k].tw.type, g_lv.m_ev[k].tw.sub),
                        DoubleToString(g_lv.m_ev[k].tw.px, _Digits), DoubleToString(g_lv.m_ev[k].t_peak, _Digits), InpH2_Retreat_Sigma, InpH3_Break_Pts);
   string used = "";
   for(int i = 0; i < NSYS; i++) if(g_lv.m_ev[k].done[i]) used += SysTag(i) + " ";
   if(used != "") s += " | ใช้สิทธิ์แล้ว: " + used;
   return s;
}

// กำแพงที่ใช้เทรดใกล้ราคาที่สุด (ข้างบน / ข้างล่าง)
string NearWallsText(double bid) {
   int    up = -1, dn = -1;
   double du = 0.0, dd = 0.0;
   for(int i = 0; i < ArraySize(g_lv.m_walls); i++) {
      if(!g_wtrade[g_lv.m_walls[i].type]) continue;
      double d = g_lv.m_walls[i].px - bid;
      if(d >= 0.0 && (up < 0 || d < du)) { up = i; du = d; }
      if(d < 0.0 && (dn < 0 || -d < dd)) { dn = i; dd = -d; }
   }
   string s = StringFormat("กำแพง %d เส้น | ", ArraySize(g_lv.m_walls));
   s += (up >= 0) ? StringFormat("บน %s %s (+%.0f จุด, ★%d)", WallName(g_lv.m_walls[up].type, g_lv.m_walls[up].sub),
                                 DoubleToString(g_lv.m_walls[up].px, _Digits), PriceToPts(du), g_lv.m_walls[up].touches + g_lv.m_walls[up].conf) : "บน -";
   s += (dn >= 0) ? StringFormat(" | ล่าง %s %s (−%.0f จุด, ★%d)", WallName(g_lv.m_walls[dn].type, g_lv.m_walls[dn].sub),
                                 DoubleToString(g_lv.m_walls[dn].px, _Digits), PriceToPts(dd), g_lv.m_walls[dn].touches + g_lv.m_walls[dn].conf) : " | ล่าง -";
   return s;
}

string PositionLines(double bid, double ask) {
   string out = "";
   for(int i = 0; i < ArraySize(g_lv.m_pos); i++) {
      if(!g_lv.m_pos[i].open) continue;
      int    d    = g_lv.m_pos[i].dir;
      double prof = (d == -1) ? PriceToPts(g_lv.m_pos[i].p_in - ask) : PriceToPts(bid - g_lv.m_pos[i].p_in);
      long   left = (long)InpTimeCut_Min * 60 - (g_last_tick_msc - g_lv.m_pos[i].msc_in) / 1000;
      out += StringFormat("\n  #%I64u %s %s %.2f @ %s | กำไร %+.0f จุด | SL %s TP %s | ตัดเวลาในอีก %d วิ",
                          g_lv.m_pos[i].ticket, SysTag(g_lv.m_pos[i].sys), (d == 1 ? "BUY" : "SELL"), g_lv.m_pos[i].lot,
                          DoubleToString(g_lv.m_pos[i].p_in, _Digits), prof, DoubleToString(g_lv.m_pos[i].sl, _Digits),
                          DoubleToString(g_lv.m_pos[i].tp, _Digits), (int)MathMax(0, left));
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
      ? StringFormat("Z_reg %+.2f | Z_SMA %+.2f (SMA20 %s, σ %.0f จุด) | Z* %+.2f",
                     g_z_reg, g_z_sma, DoubleToString(g_sma_mean, _Digits), PriceToPts(g_sma_sd), ZStar(g_z_sma))
      : "รอข้อมูลแท่งเทียน...";
   string news_str = NextNewsText(now);
   long   now_msc  = MathMax(g_last_tick_msc, (long)now * 1000);
   string sys = "", wt = "";
   for(int i = 0; i < NSYS; i++) sys += StringFormat("%s %s  ", SysTag(i), (g_en[i] ? "✅" : "⛔"));
   for(int i = 0; i < NW; i++) if(g_wtrade[i]) wt += "W" + IntegerToString(i + 1) + " ";
   string msg = StringFormat("=== 🧱 7-Lines Wall EA v1.00 | จุด A: Z ตัวใด > %.1f | %s| เทรดกำแพง %s===\n", InpA_Z, sys, wt);
   msg += StringFormat("Z (%s, %d) : %s%s\n", EnumToString(InpZ_Timeframe), InpZ_Period, z_str, (news_str == "" ? "" : " | " + news_str));
   msg += NearWallsText(bid) + "\n";
   msg += EventText(0, now_msc) + "\n";
   msg += EventText(1, now_msc) + "\n";
   msg += StringFormat("ออเดอร์ : BUY %d / SELL %d | สเปรด %.0f / %.0f จุด | hit&run: SL หลังกำแพง %.0f จุด, TP %.1fR, ตัดเวลา %d นาที\n",
                       buys, sells, PriceToPts(ask - bid), InpMaxSpread_Pts, InpSLBeyond_Pts, InpTP_R, InpTimeCut_Min);
   msg += "เวลาตลาด : " + TimeStateText(ts, now) + "\n";
   msg += "สถานะล่าสุด : " + g_last_status;
   if(InpShowReplay) msg += "\n" + ReplayStatsText();
   msg += PositionLines(bid, ask);
   if(msg != g_last_comment) {
      g_last_comment = msg;
      Comment(msg);
   }
}

//====================================================================
// 🔘 ปุ่มวิธีเข้า + ป้ายไม้ไม่ซ้อนกัน
//====================================================================
// เวลาภายในแท่ง (TF ของ Z) เช่น "น.07:32" = นาทีที่ 7 วินาทีที่ 32 นับจากเปิดแท่ง
string BarMinText(datetime t) {
   long sec = (long)t - (long)BarStartOf(t);
   return StringFormat("น.%02d:%02d", (int)(sec / 60), (int)(sec % 60));
}

string SysGVName(int s) { return StringFormat("7LWEA_%s_%I64d_%s", _Symbol, InpMagic, SysTag(s)); }

void SysEnableInit() {
   int  r       = UninitializeReason();
   bool restore = (r == REASON_CHARTCHANGE || r == REASON_RECOMPILE || r == REASON_ACCOUNT);
   g_en[M_H1] = InpEnH1; g_en[M_H2] = InpEnH2; g_en[M_H3] = InpEnH3;
   for(int s = 0; s < NSYS; s++) {
      if(restore && GlobalVariableCheck(SysGVName(s))) g_en[s] = (GlobalVariableGet(SysGVName(s)) > 0.5);
      GlobalVariableSet(SysGVName(s), g_en[s] ? 1.0 : 0.0);
   }
}

void DrawSysButtons() {
   if(!g_draw) return;
   for(int s = 0; s < NSYS; s++) {
      string nm = BTN_PREFIX + IntegerToString(s);
      if(ObjectFind(0, nm) < 0) {
         ObjectCreate(0, nm, OBJ_BUTTON, 0, 0, 0);
         ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_LOWER);
         ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, 10 + s * 64);
         ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, 34);
         ObjectSetInteger(0, nm, OBJPROP_XSIZE, 60);
         ObjectSetInteger(0, nm, OBJPROP_YSIZE, 22);
         ObjectSetString(0,  nm, OBJPROP_FONT, "Arial Bold");
         ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, 9);
         ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
      }
      ObjectSetString(0,  nm, OBJPROP_TEXT, SysTag(s) + (g_en[s] ? " ON" : " OFF"));
      ObjectSetInteger(0, nm, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, nm, OBJPROP_BGCOLOR, g_en[s] ? clrSeaGreen : clrDimGray);
      ObjectSetInteger(0, nm, OBJPROP_STATE, false);
      ObjectSetString(0,  nm, OBJPROP_TOOLTIP, StringFormat("คลิกเพื่อ%s %s (Tick Replay จะเล่นซ้ำใหม่ตามระบบที่เปิด)", (g_en[s] ? "ปิด" : "เปิด"), SysTag(s)));
   }
}

void ToggleSys(int s) {
   if(s < 0 || s >= NSYS) return;
   g_en[s] = !g_en[s];
   GlobalVariableSet(SysGVName(s), g_en[s] ? 1.0 : 0.0);
   if(s == M_H1) { g_lv.m_ev[0].h1_on = false; g_lv.m_ev[1].h1_on = false; }
   ObjectsDeleteAll(0, OBJ_PREFIX + "RP_");
   ReplayReset();
   g_lay_sig     = "";
   g_last_status = StringFormat("%s %s (ปุ่ม) — Tick Replay เริ่มเล่นซ้ำใหม่", SysTag(s), (g_en[s] ? "เปิด" : "ปิด"));
   PrintFormat("🔘 %s", g_last_status);
   DrawSysButtons();
}

// จัดป้ายไม้ (Tick Replay + ไม้จริง) ที่มองเห็นไม่ให้ซ้อนกัน: เรียงตามเวลา, ป้ายที่ทับป้ายก่อนหน้าถูกเลื่อนขึ้น/ลงทีละแถว
//   + เส้นโยงจากจุดเข้าไม้ถึงป้ายที่ถูกเลื่อน — จัดใหม่เมื่อซูม / เลื่อน / สเกลราคา / มีไม้ใหม่
void LayoutTradeLabels() {
   if(!g_draw) return;
   long   first = ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR);
   long   wb    = ChartGetInteger(0, CHART_WIDTH_IN_BARS);
   long   hpx   = ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   long   wpx   = ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   double pmax  = ChartGetDouble(0, CHART_PRICE_MAX);
   double pmin  = ChartGetDouble(0, CHART_PRICE_MIN);
   string sig   = StringFormat("%I64d|%I64d|%I64d|%I64d|%.5f|%.5f|%d|%d", first, wb, hpx, wpx, pmax, pmin, ArraySize(g_rt), ArraySize(g_marks));
   if(sig == g_lay_sig) return;
   g_lay_sig = sig;
   if(hpx <= 0 || pmax <= pmin) return;
   datetime t_from = iTime(_Symbol, PERIOD_CURRENT, (int)first);
   if(t_from == 0) return;
   t_from -= (datetime)(PeriodSeconds(PERIOD_CURRENT) * 60);   // ป้ายทางซ้ายที่ข้อความยาวเข้ามาในจอ
   double ppx = (pmax - pmin) / (double)hpx;

   string   nm[];
   datetime tt[];
   double   pp[];
   bool     rt[];   // true = ข้อความอยู่ซ้ายของจุด (ANCHOR_RIGHT)
   color    cc[];
   int      n = 0;
   for(int i = 0; i < ArraySize(g_rt); i++) {
      datetime t = (datetime)(g_rt[i].msc_in / 1000);
      if(t < t_from) continue;
      string name = OBJ_PREFIX + "RP_T_" + IntegerToString(g_rt[i].msc_in) + "_" + IntegerToString(i);
      if(ObjectFind(0, name) < 0) continue;
      ArrayResize(nm, n + 1); ArrayResize(tt, n + 1); ArrayResize(pp, n + 1); ArrayResize(rt, n + 1); ArrayResize(cc, n + 1);
      nm[n] = name; tt[n] = t; pp[n] = g_rt[i].p_in; rt[n] = true; cc[n] = (color)ObjectGetInteger(0, name, OBJPROP_COLOR);
      n++;
   }
   for(int k = 0; k < ArraySize(g_marks); k++) {
      if(g_marks[k].t < t_from) continue;
      string name = OBJ_PREFIX + "EN_T_" + IntegerToString((long)g_marks[k].deal);
      if(ObjectFind(0, name) < 0) continue;
      ArrayResize(nm, n + 1); ArrayResize(tt, n + 1); ArrayResize(pp, n + 1); ArrayResize(rt, n + 1); ArrayResize(cc, n + 1);
      nm[n] = name; tt[n] = g_marks[k].t; pp[n] = g_marks[k].price; rt[n] = false; cc[n] = InpClrEntryGap;
      n++;
   }
   for(int a = 1; a < n; a++) {   // เรียงตามเวลา
      int b = a;
      while(b > 0 && tt[b - 1] > tt[b]) {
         string s0 = nm[b]; nm[b] = nm[b - 1]; nm[b - 1] = s0;
         datetime t0 = tt[b]; tt[b] = tt[b - 1]; tt[b - 1] = t0;
         double p0 = pp[b]; pp[b] = pp[b - 1]; pp[b - 1] = p0;
         bool r0 = rt[b]; rt[b] = rt[b - 1]; rt[b - 1] = r0;
         color c0 = cc[b]; cc[b] = cc[b - 1]; cc[b - 1] = c0;
         b--;
      }
   }
   double x0s[], x1s[], y0s[], y1s[];
   int    placed = 0;
   for(int k = 0; k < n; k++) {
      int x = 0, y = 0;
      if(!ChartTimePriceToXY(0, 0, tt[k], pp[k], x, y)) continue;
      uint tw = 0, th = 0;
      TextSetFont(ObjectGetString(0, nm[k], OBJPROP_FONT), -10 * (int)ObjectGetInteger(0, nm[k], OBJPROP_FONTSIZE));
      TextGetSize(ObjectGetString(0, nm[k], OBJPROP_TEXT), tw, th);
      double w   = (double)tw + 4.0, h = (double)th + 2.0;
      double xa  = rt[k] ? x - w : x, xb = rt[k] ? x : x + w;
      int    off = 0;
      for(int tryi = 0; tryi <= 16; tryi++) {
         int    o   = (tryi == 0) ? 0 : ((tryi % 2 == 1) ? (tryi + 1) / 2 : -(tryi / 2));
         double ya  = y + o * h - h / 2.0, yb = ya + h;
         bool   hit = false;
         for(int q = 0; q < placed && !hit; q++)
            hit = (xa < x1s[q] && xb > x0s[q] && ya < y1s[q] && yb > y0s[q]);
         if(!hit) { off = o; break; }
      }
      double yy = y + off * h;
      double np = pp[k] - (yy - y) * ppx;
      if(MathAbs(ObjectGetDouble(0, nm[k], OBJPROP_PRICE) - np) > _Point) ObjectSetDouble(0, nm[k], OBJPROP_PRICE, np);
      string kn = nm[k] + "_K";
      if(off != 0) {
         if(ObjectFind(0, kn) < 0) {
            ObjectCreate(0, kn, OBJ_TREND, 0, tt[k], pp[k], tt[k], np);
            ObjectSetInteger(0, kn, OBJPROP_STYLE, STYLE_DOT);
            ObjectSetInteger(0, kn, OBJPROP_RAY_RIGHT, false);
            ObjectSetInteger(0, kn, OBJPROP_RAY_LEFT, false);
            ObjectSetInteger(0, kn, OBJPROP_BACK, true);
            ObjectSetInteger(0, kn, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, kn, OBJPROP_HIDDEN, true);
         }
         ObjectSetInteger(0, kn, OBJPROP_COLOR, cc[k]);
         ObjectMove(0, kn, 0, tt[k], pp[k]);
         ObjectMove(0, kn, 1, tt[k], np);
      }
      else if(ObjectFind(0, kn) >= 0) ObjectDelete(0, kn);
      ArrayResize(x0s, placed + 1); ArrayResize(x1s, placed + 1); ArrayResize(y0s, placed + 1); ArrayResize(y1s, placed + 1);
      x0s[placed] = xa; x1s[placed] = xb; y0s[placed] = yy - h / 2.0; y1s[placed] = yy + h / 2.0;
      placed++;
   }
}

//====================================================================
// 🚀 EVENT HANDLERS
//====================================================================
int OnInit() {
   if(InpZ_Period < 2) { Print("❌ Period ต้องอย่างน้อย 2"); return(INIT_PARAMETERS_INCORRECT); }
   if(InpBarZBars < 1 || InpBarZBars > 20000) { Print("❌ InpBarZBars ต้องอยู่ระหว่าง 1-20000"); return(INIT_PARAMETERS_INCORRECT); }
   if(InpReplayDays < 1 || InpReplayDays > 60) { Print("❌ InpReplayDays ต้องอยู่ระหว่าง 1-60"); return(INIT_PARAMETERS_INCORRECT); }
   if(InpA_Z <= 0.0 || InpA_EndZ < 0.0 || InpA_EndZ >= InpA_Z || InpA_MaxIdle_Min < 1) {
      Print("❌ ค่าจุด A ไม่ถูกต้อง (0 ≤ จบ < จุด A, หมดอายุ ≥ 1 นาที)");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpH1_MaxDist_Sigma <= 0.0 || InpH2_Retreat_Sigma <= 0.0 || InpH3_Break_Pts <= 0.0 || InpSLBeyond_Pts <= 0.0 ||
      InpLot <= 0.0 || InpTP_R <= 0.0 || InpTimeCut_Min < 0) {
      Print("❌ ค่าวิธีเข้า / hit&run ไม่ถูกต้อง");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpW1_Days < 1 || InpW4_Days < 1 || InpW4_Fractal < 1 || InpW5_Hours < 1 || InpW5_Bin_Pts <= 0.0 || InpW5_Top < 0 ||
      InpW3_Step < 0.0 || InpTouch_Pts <= 0.0 || InpTouchDays < 1 || InpConf_Pts < 0.0 ||
      InpAsiaStartH < 0 || InpAsiaEndH > 24 || InpAsiaStartH >= InpAsiaEndH || InpLondonStartH < 0 || InpLondonEndH > 24 || InpLondonStartH >= InpLondonEndH) {
      Print("❌ ค่ากำแพงไม่ถูกต้อง");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpSigmaFloorMult < 0.0 || InpNewsBlock_Min < 0) { Print("❌ ค่าพื้นตัวหาร / ช่วงข่าว ไม่ถูกต้อง"); return(INIT_PARAMETERS_INCORRECT); }
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING) {
      Print("❌ EA นี้ต้องใช้บัญชีแบบ Hedging");
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

   g_sys_clr[M_H1] = clrGold; g_sys_clr[M_H2] = clrOrange; g_sys_clr[M_H3] = clrDodgerBlue;
   g_wtrade[0] = InpTradeW1; g_wtrade[1] = InpTradeW2; g_wtrade[2] = InpTradeW3;
   g_wtrade[3] = InpTradeW4; g_wtrade[4] = InpTradeW5; g_wtrade[5] = InpTradeW6;
   g_wshow[0] = InpShowW1; g_wshow[1] = InpShowW2; g_wshow[2] = InpShowW3;
   g_wshow[3] = InpShowW4; g_wshow[4] = InpShowW5; g_wshow[5] = InpShowW6;
   g_wclr[0] = InpClrW1; g_wclr[1] = InpClrW2; g_wclr[2] = InpClrW3;
   g_wclr[3] = InpClrW4; g_wclr[4] = InpClrW5; g_wclr[5] = InpClrW6;

   g_barz_bar = 0;
   ArrayResize(g_zl_names, 0);
   ArrayResize(g_zl_times, 0);
   g_bar_changed   = false;
   g_last_tick_msc = 0;
   g_zc.ok         = false;
   g_lv.Reset();
   ReplayReset();
   g_zbar_time      = 0;
   g_z_ready        = false;
   g_blk_valid      = false;
   g_news_loaded    = 0;
   g_news_ok        = false;
   g_prev_close_zr  = 0.0;
   g_prev_close_zs  = 0.0;
   ArrayResize(g_marks, 0);
   ArrayResize(g_wall_objs, 0);
   g_marks_bar = 0;
   g_wall_bar  = 0;
   g_newsviz_loaded = 0;
   ArrayResize(g_newsviz_names, 0);
   ArrayResize(g_news_times, 0);
   ArrayResize(g_news_names, 0);
   g_last_comment   = "";
   g_line_main = g_line_sell = g_line_buy = 0.0;
   g_line_sma_main = g_line_sma_sell = g_line_sma_buy = 0.0;
   g_live_z_text = ""; g_live_z_y = -1;

   RefreshNews(ServerNow());
   SysEnableInit();
   g_lay_sig = "";
   LiveRestore();

   ObjectsDeleteAll(0, OBJ_PREFIX);
   LiveWallRebuild();
   LoadEntryMarksFromHistory();
   DrawSysButtons();

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
   LiveWallRebuild();
   UpdateLiveZLabel(tk.bid);
   datetime now = ServerNow();
   int      ts  = GetTimeState(now);
   g_lv.Step(g_last_tick_msc, tk.bid, tk.ask, g_zc, ts, EntryBlockReason(ts, tk.bid, tk.ask, now));
}

void OnTimer() {
   datetime now = ServerNow();
   int ts = GetTimeState(now);
   RefreshNews(now);
   LiveSync();
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   bool   zok = (bid > 0.0 && ask > 0.0 && UpdateZ(bid));
   if(zok) {
      LiveWallRebuild();
      g_lv.Step(MathMax(g_last_tick_msc, (long)now * 1000), bid, ask, g_zc, ts, EntryBlockReason(ts, bid, ask, now));
   }
   if(g_draw) {
      UpdateZLines();
      UpdateBarZLabels();
      UpdateEntryMarks();
      ReplayStep();
      LayoutTradeLabels();
      LoadNewsHistory();
      if(bid > 0.0) UpdateLiveZLabel(bid);
      UpdateDashboard(ts, now);
      ChartRedraw(0);
   }
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
   if(id == CHARTEVENT_OBJECT_CLICK && StringFind(sparam, BTN_PREFIX) == 0) {
      ToggleSys((int)StringToInteger(StringSubstr(sparam, StringLen(BTN_PREFIX))));
      ChartRedraw(0);
      return;
   }
   if(id != CHARTEVENT_CHART_CHANGE || !g_draw) return;
   LayoutTradeLabels();
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
}
//+------------------------------------------------------------------+
