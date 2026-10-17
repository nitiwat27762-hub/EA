//+------------------------------------------------------------------+
//|                                       Seven_Lines_Counter_EA.mq5 |
//|      Fast Mean-Reversion Z-Score EA for XAUUSD (Indicator v8.82)  |
//+------------------------------------------------------------------+
//
// 🆕 v3.00
//  • Z แบบเส้นถดถอย (Regression Z): เส้นกลาง = เส้นถดถอยเชิงเส้น 20 แท่ง (รวมแท่งปัจจุบัน)
//    ตัวหาร = StdDev ของส่วนเบี่ยงเบนรอบเส้นถดถอย (ไม่นับความชันเทรนด์เป็นความผันผวน)
//    + พื้นขั้นต่ำของตัวหาร = InpSigmaFloorMult × StdDev ของการเปลี่ยนแปลงราคาต่อแท่ง (กัน Z พุ่งตอนเทรนด์เรียบ)
//      (ไม่ใช้ StdDev แบบ SMA เป็นพื้น เพราะมันพองตามความชันเทรนด์ — จะกด Z กลับไปเหมือนเดิม)
//    → แก้ปัญหา SMA ชันแล้ว Z ไม่แตะ (Z แบบ SMA ในเทรนด์เส้นตรงตันที่ ≈ 1.65 เสมอ)
//  • ป้องกันข่าว: ตัวจับช็อก (ช่วงแกว่งแท่ง ≥ 3×ATR → งดถึง 30 นาทีหลังแท่งช็อกปิด)
//    + กรองความต่อเนื่อง (แท่งที่เพิ่งปิดค้างในโซนสุดขั้วฝั่งเดียวกัน → ไม่สวน)
//    + ปฏิทินข่าว USD ระดับ High (ตัวเลือก, ใช้ไม่ได้ใน Strategy Tester)
//
// 🆕 v6.00: ไม้ซ้ำแบบ Double-tap (แทนการนับเวลา 10 วินาที)
//  • หลังเปิดไม้ ต้องเห็น "เริ่มดีด" ก่อน: Z ถอยจากจุดสุดขั้ว ≥ InpReEntryRetreatZ
//  • แล้ว "ถูกกระชากกลับ": Z ถึงเกณฑ์อีกครั้ง (ข้ามกลับจากใต้เกณฑ์ หรือดันกลับ ≥ InpReEntryRetreatZ จากจุดต่ำสุดหลังดีด)
//  • ต้องอยู่ในแท่ง (TF ของ Z) เดียวกับไม้แรก, ราคาไม่แย่กว่าไม้ก่อน (+ InpReEntryMinDist_Pts),
//    ไม้ซ้ำไม่เกิน InpReEntryMax ต่อชุด
//  • ชุดไม้จบทันทีเมื่อไม้ในชุดโดนตัด 60 วินาทีหรือชน SL ขาดทุน (สมมติฐานดีดกลับล้ม) / หรือขึ้นแท่งใหม่
//
// 🆕 v5.10: มาร์กจุดเปิดไม้บนกราฟ
//  • ลูกศร ณ ราคาเปิดไม้ + เส้นประแนวตั้งถึงปลายไส้ของแท่ง (TF ของ Z) + ระยะห่างเป็นจุด
//    SELL วัดถึง High / BUY วัดถึง Low — แท่งที่ยังไม่ปิดอัปเดตทุก 1 วินาที
//  • ดึงจาก Deal History ของ EA (Magic) ย้อนหลังเท่าช่วงป้าย Z + ไม้ใหม่ผ่าน OnTradeTransaction
//
// 🆕 v5.00: ตรรกะเข้าไม้ใหม่ + วาดย้อนหลังแบบเบา
//  • ไม้แรก: Z_reg และ Z_SMA ถึงเกณฑ์ทั้งคู่ (ตาม InpEntryLogic) → ยิงทันที ไม่รอ Z ย่อ
//  • ไม้ซ้ำ: ทุก 10 วินาทีหลังไม้ล่าสุด ถ้า Z ยังถึงเกณฑ์ (v6.00 แทนด้วย Double-tap)
//    + ตัวเลือก: ไม้ซ้ำต้องได้ราคาดีกว่าไม้ก่อน InpReEntryMinDist_Pts จุด
//  • ชุดไม้จบเมื่อ Z หลุดเกณฑ์ → ชุดใหม่ต้องรอ Z ถอยกลับ ReArm ก่อน
//  • เส้น 7 เส้นตั้งชื่อช่วงเส้นตามเวลาแท่ง: ขึ้นแท่งใหม่สร้างแค่ช่วงใหม่ + ลบช่วงที่หลุดหน้าต่าง (ภาระคงที่)
//  • ป้าย Z บนแท่งค่าเริ่มต้น 2,000 แท่ง
//
// 🆕 v4.30: Z แบบ SMA20 เทียบกับ Z แบบเส้นถดถอย
//  • Z_SMA = (Bid − SMA20) / StdDev20 (รวมแท่งปัจจุบัน แบบเดียวกับ v1-v2) คำนวณคู่กับ Z_reg ทุก Tick
//  • (v5.00 แทนด้วย InpEntryLogic: ทั้งคู่ / Regression / SMA)
//  • เส้นแนวนอนชุด SMA (กลาง / SELL / BUY) แยกสีจากชุด Regression
//  • ป้าย Z สดและป้ายบนแท่งแสดงทั้ง R (Regression) และ S (SMA)
//    ป้ายบนแท่งขึ้นเมื่อตัวใดตัวหนึ่งถึงเกณฑ์ — สีเต็มถ้าตัวที่ใช้เทรดถึง, สีเทาถ้าถึงแค่ตัวเทียบ
//
// 🆕 v4.20
//  • ตั้งสีเส้น / ป้ายทุกอย่างได้เองจาก Input (กลุ่ม 8)
//  • ป้ายค่า Z บนทุกแท่ง (TF ของ Z) ที่ Z ถึงเกณฑ์: เหนือแท่ง = Z ที่ราคา High (≥ +SellZ),
//    ใต้แท่ง = Z ที่ราคา Low (≤ −BuyZ) — คำนวณแบบเดียวกับ Z สด (ราคาปิด n−1 แท่งก่อนหน้า + ราคาสุดขั้วของแท่ง)
//    ย้อนหลังคำนวณครั้งเดียวตอนเริ่ม, แท่งปัจจุบันอัปเดตทุก 1 วินาที, ขึ้นแท่งใหม่ยืนยันค่าจริงของแท่งที่ปิด
//
// 🆕 v4.10: แก้การแสดงผล
//  • ป้าย Z สดเปลี่ยนเป็น OBJ_LABEL ติดขอบขวากราฟที่ความสูงของราคาปัจจุบัน (เดิมวางไว้ในอนาคต
//    2 แท่ง ซึ่งมองไม่เห็นถ้าไม่ได้เปิด Chart shift) + ตามการเลื่อน/ซูมกราฟผ่าน OnChartEvent
//  • สั่ง ChartRedraw ทุก 1 วินาที (วัตถุแสดงผลแม้ไม่มี Tick เข้า) + รายงานสถานะการวาดเส้น 7 เส้นบน Dashboard/Log
//
// 🆕 v4.00: รวม Indicator 7 เส้นเข้ามาใน EA (ไฟล์เดียวจบ ไม่ต้องพึ่ง Seven_Lines_Exhaustion_Ind.ex5)
//  • คำนวณเส้น Main(SMA), L1 EMA, L2 LWMA, L3 HMA, L4 LSMA, L5 ALMA, L6 Kinematic บน TF ของกราฟ
//  • วาดเป็นเส้น object ย้อนหลัง InpLinesBars แท่ง (v5.00: แตะ object เฉพาะช่วงที่เปลี่ยน)
//    ระหว่างแท่งขยับแค่ช่วงเส้นของแท่งปัจจุบันทุก 1 วินาที → CPU ต่ำ
//
// 🆕 v3.10: ป้ายค่า Z สด ณ ราคาปัจจุบัน (ลอยข้างแท่งล่าสุดที่ระดับ Bid, เปลี่ยนสีตามโซน)
//
// 🎯 นิยามระบบ (v2.00)
//  สวนกลับค่าที่ผิดปกติ (Z ≥ +2.5 / Z ≤ −3.0) ที่ "ควรดีดกลับอย่างรวดเร็ว"
//  ถ้าไม่ดีดกลับภายในเวลาที่กำหนด = สมมติฐานผิด → ออกทันที
//
// 📋 ตรรกะการเข้าไม้ (v5.00, แยก SELL / BUY)
//  ปลดไก ──(Z ถอยกลับเกิน ReArm)──► พร้อมยิง ──(Z ถึงเกณฑ์ตาม InpEntryLogic)──► ไม้แรกทันที
//  ──► ในชุดไม้ (แท่งเดียวกัน): Z ดีดกลับ ≥ 0.3 แล้วกระชากกลับถึงเกณฑ์ → ไม้ซ้ำ (≤ 2 ไม้)
//  ──(ขึ้นแท่งใหม่ / ไม้ในชุดโดนตัดหรือชน SL)──► จบชุด → ปลดไกเมื่อ Z ถอยกลับ ReArm
//  • ทุกไม้ต้องผ่านตัวกรอง (เวลา, สเปรด, พัก SL, งดแท่ง, ช็อก, ข่าว, ความต่อเนื่อง, จำนวนไม้)
//  • เริ่ม EA ในสถานะปลดไก (ไม่เข้ากลางทางเมื่อ Z เกินเกณฑ์อยู่แล้ว)
//
// 📋 ตรรกะการจัดการไม้
//  • TP / SL คงที่ตั้งแต่เปิดไม้
//  • ภายใน QuickWindow วินาทีแรก ตรวจทุก 1 วินาที: กำไรถึงจุดเริ่มไล่จี้ → เปิดระบบไล่จี้ทันที
//  • ครบ QuickWindow แล้วระบบไล่จี้ยังไม่ทำงาน → ตัดจบ + งดเปิดไม้ใหม่ทั้งแท่ง (TF ของ Z)
//  • หลังเปิดระบบไล่จี้ ขยับโล่ทุก TrailInterval วินาที (ทางเดียว)
//  • ชน SL แบบขาดทุน → พักเข้าไม้ทั้งสองฝั่ง SLCooldown นาที
//  • ห้ามเข้า 1 ชม.แรกหลังตลาดเปิดสัปดาห์ / ปิดทุกไม้ 30 นาทีก่อนตลาดปิดสัปดาห์
//
// ⚡ การประหยัด CPU
//  • Z: แคช Σy, Σxy, Σy² ของแท่งที่ปิดแล้ว + ATR คำนวณเฉพาะตอนขึ้นแท่งใหม่ (ต่อ Tick ไม่กี่บรรทัดคณิต)
//  • จัดการไม้ / Dashboard / เส้น ทำบน OnTimer 1 วินาที, ตรวจ SL ผ่าน OnTradeTransaction (ไม่ไล่ประวัติ)
//  • Dashboard เขียนเฉพาะเมื่อข้อความเปลี่ยน, ไม่วาดอะไรใน Tester แบบไม่เปิด Visual
//
#property copyright   "Commander's Quant System"
#property version     "6.00"
#property description "สวนกลับค่า Z ผิดปกติที่ควรดีดกลับเร็ว สำหรับ XAUUSD (บัญชี Hedging)"

#include <Trade\Trade.mqh>

//====================================================================
// 🎛️ INPUT PARAMETERS
//====================================================================
enum ENUM_ENTRY_LOGIC {
   ENTRY_BOTH       = 0,   // ต้องถึงเกณฑ์ทั้ง Z_reg และ Z_SMA
   ENTRY_REGRESSION = 1,   // Z_reg อย่างเดียว
   ENTRY_SMA        = 2    // Z_SMA อย่างเดียว
};

input group "=== 1. Z-Score & จุดเข้า ==="
input ENUM_TIMEFRAMES InpZ_Timeframe       = PERIOD_M15; // Timeframe ที่ใช้คำนวณ Z
input int             InpZ_Period          = 20;         // จำนวนแท่งของ SMA / StdDev
input ENUM_ENTRY_LOGIC InpEntryLogic       = ENTRY_BOTH; // เงื่อนไข Z ที่ใช้เข้าไม้
input double          InpSellZ             = 2.50;       // เฝ้า SELL เมื่อ Z ≥ +ค่านี้ (สวนขาขึ้น)
input double          InpBuyZ              = 3.00;       // เฝ้า BUY เมื่อ Z ≤ −ค่านี้ (สวนขาลง)
input double          InpReEntryRetreatZ   = 0.30;       // ไม้ซ้ำ: Z ต้องดีดกลับจากจุดสุดขั้วเท่านี้ แล้วกระชากกลับถึงเกณฑ์
input int             InpReEntryMax        = 2;          // ไม้ซ้ำสูงสุดต่อชุด (ไม่รวมไม้แรก, 0 = ปิดไม้ซ้ำ)
input double          InpReEntryMinDist_Pts = 0.0;       // ไม้ซ้ำ: ราคาต้องดีกว่าไม้ก่อนอย่างน้อย (จุด, 0 = แค่ไม่แย่กว่า)
input double          InpReArmBuffer       = 0.50;       // ระยะ Z ที่ต้องถอยกลับก่อนเริ่มชุดไม้ใหม่ฝั่งเดิม
input double          InpSigmaFloorMult    = 0.50;       // ตัวหาร Z ต้องไม่น้อยกว่า ค่านี้ × StdDev ของการเปลี่ยนแปลงราคาต่อแท่ง

input group "=== 2. ออเดอร์ ==="
input double          InpLot               = 0.01;       // Lot คงที่ต่อไม้
input int             InpMaxPositions      = 5;          // จำนวนไม้สูงสุด (รวมทั้งสองฝั่ง)
input double          InpTP_Pts            = 20000.0;    // Take Profit (จุด)
input double          InpSL_Pts            = 10000.0;    // Stop Loss (จุด)
input double          InpSlippage_Pts      = 300.0;      // Slippage สูงสุดตอนส่งคำสั่ง (จุด)
input long            InpMagic             = 880100;     // Magic Number
input string          InpOrderComment      = "7L-CNT";   // คอมเมนต์ออเดอร์

input group "=== 3. ไล่จี้กำไร ==="
input double          InpTrailStart_Pts    = 8000.0;     // เริ่มไล่จี้เมื่อกำไรถึง (จุด)
input double          InpTrailDist_Pts     = 6000.0;     // ระยะโล่ห่างจากราคา (จุด)
input int             InpTrailInterval_Sec = 5;          // ขยับโล่ทุกกี่วินาที (หลังเริ่มไล่จี้แล้ว)

input group "=== 4. กฎดีดกลับเร็ว ==="
input int             InpQuickWindow_Sec   = 60;         // ไม้ต้องเข้าระบบไล่จี้ภายในกี่วินาที ไม่งั้นตัดจบ (0 = ปิด)
input int             InpSLCooldown_Min    = 5;          // พักเข้าไม้ทั้งสองฝั่งหลังชน SL ขาดทุน (นาที, 0 = ปิด)

input group "=== 5. ป้องกันข่าว / แรงต่อเนื่อง ==="
input bool            InpUseShockFilter    = true;       // [ช็อก] งดเข้าเมื่อช่วงแกว่งแท่ง ≥ ATR × ตัวคูณ
input int             InpShockATR_Period   = 14;         // [ช็อก] จำนวนแท่งของ ATR
input double          InpShockATR_Mult     = 3.0;        // [ช็อก] ตัวคูณ ATR
input int             InpShockBlock_Min    = 30;         // [ช็อก] งดเข้าไม้ต่อกี่นาทีหลังแท่งช็อกปิด
input bool            InpUsePersistFilter  = true;       // [ต่อเนื่อง] ไม่สวนถ้าแท่งที่เพิ่งปิดค้างในโซนสุดขั้วฝั่งเดียวกัน
input double          InpPersistZ          = 2.0;        // [ต่อเนื่อง] |Z ตอนปิดแท่ง| ที่ถือว่าค้างโซนสุดขั้ว
input bool            InpUseNewsCalendar   = false;      // [ข่าว] งดเข้ารอบข่าวระดับ High (ใช้ไม่ได้ใน Tester)
input string          InpNewsCurrency      = "USD";      // [ข่าว] สกุลเงินของข่าว
input int             InpNewsBefore_Min    = 15;         // [ข่าว] งดก่อนข่าวกี่นาที
input int             InpNewsAfter_Min     = 30;         // [ข่าว] งดหลังข่าวกี่นาที

input group "=== 6. ตัวกรองทั่วไป ==="
input double          InpMaxSpread_Pts     = 800.0;      // สเปรดสูงสุดที่ยอมให้เข้าไม้ (จุด)
input int             InpNoTradeAfterOpen_Min = 60;      // ห้ามเข้าไม้หลังตลาดเปิดสัปดาห์ (นาที)
input int             InpCloseBeforeClose_Min = 30;      // ปิดทุกไม้ก่อนตลาดปิดสัปดาห์ (นาที)

input group "=== 7. การแสดงผล ==="
input bool            InpShowDashboard     = true;       // แสดง Dashboard
input bool            InpShowZLines        = true;       // แสดงเส้นแนวนอนระดับ Z ชุด Regression
input bool            InpShowSmaZLines     = true;       // แสดงเส้นแนวนอนระดับ Z ชุด SMA20 (เปรียบเทียบ)
input bool            InpShow7Lines        = true;       // วาดเส้น 7 เส้น (คำนวณในตัว EA บน TF ของกราฟ)
input int             InpFastPeriod        = 10;         // Fast Period ของเส้น L1-L5
input int             InpLinesBars         = 200;        // จำนวนแท่งย้อนหลังที่วาดเส้น 7 เส้น
input bool            InpShowLiveZ         = true;       // แสดงป้ายค่า Z สด ณ ราคาปัจจุบัน
input int             InpLiveZFontSize     = 11;         // ขนาดตัวอักษรป้าย Z สด
input int             InpLiveZOffsetPx     = 10;         // ระยะห่างป้าย Z สดจากขอบขวาของกราฟ (พิกเซล)
input bool            InpShowBarZ          = true;       // แสดงป้ายค่า Z บนแท่งที่ Z ถึงเกณฑ์
input int             InpBarZBars          = 2000;       // จำนวนแท่งย้อนหลัง (TF ของ Z) ที่แสดงป้าย
input int             InpBarZFontSize      = 8;          // ขนาดตัวอักษรป้าย Z บนแท่ง
input double          InpBarZOffset_Pts    = 300.0;      // ระยะห่างป้ายจากไส้เทียน (จุด)
input bool            InpShowEntryMarks    = true;       // มาร์กจุดเปิดไม้ + ระยะห่างถึงปลายไส้เทียน

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

// สถานะไกยิงของแต่ละฝั่ง
#define PH_WAIT_RETREAT 0   // หลังเปิดไม้: รอ Z ดีดกลับจากจุดสุดขั้ว
#define PH_WAIT_RETEST  1   // ดีดแล้ว: รอ Z ถูกกระชากกลับถึงเกณฑ์

struct SideState {
   bool     armed;       // Z ถอยกลับมาแล้ว พร้อมเริ่มชุดไม้ใหม่
   bool     in_series;   // อยู่ในชุดไม้ (แท่งเดียวกับไม้แรก)
   datetime series_bar;  // เวลาเปิดแท่ง (TF ของ Z) ของไม้แรก
   datetime last_entry;  // เวลาเปิดไม้ล่าสุดของชุด
   double   last_price;  // ราคาเปิดไม้ล่าสุดของชุด
   int      count;       // จำนวนไม้ที่เปิดในชุดนี้ (รวมไม้แรก)
   int      phase;       // PH_*
   double   ext;         // Z สุดขั้วหลังไม้ล่าสุด
   double   trough;      // Z ที่ถอยลึกสุดหลังเริ่มดีด
};

CTrade    trade;
double    g_pmult        = 1.0;
bool      g_draw         = true;

// --- Z engine (แคชผลรวมของแท่งที่ปิดแล้ว, ค่าเลื่อนจุดอ้างอิง g_ref) ---
datetime  g_zbar_time    = 0;
bool      g_z_ready      = false;
double    g_ref          = 0.0;
double    g_sumY         = 0.0;   // Σy  ของแท่งปิด (x = 0..n-2)
double    g_sumXY        = 0.0;   // Σxy
double    g_sumYY        = 0.0;   // Σy²
double    g_sumD         = 0.0;   // Σd  ของส่วนต่างราคาปิดต่อแท่ง (ระหว่างแท่งปิด)
double    g_sumDD        = 0.0;   // Σd²
double    g_last_close   = 0.0;   // ราคาปิดแท่งล่าสุด (ใช้หาส่วนต่างของแท่งปัจจุบัน)
bool      g_z_valid      = false;
double    g_z            = 0.0;   // Z ที่มีผลตามเงื่อนไขเข้าไม้ (ทั้งคู่ = ตัวที่ใกล้ 0 กว่า)
double    g_z_reg        = 0.0;   // Regression Z
double    g_center       = 0.0;   // ราคาเส้นกลาง Regression (เส้นถดถอยที่แท่งปัจจุบัน)
double    g_sigma        = 0.0;   // ตัวหาร Regression ที่ใช้จริง
double    g_sma_mean     = 0.0;   // ราคา SMA20 (รวมแท่งปัจจุบัน)
double    g_sma_sd       = 0.0;   // StdDev20
bool      g_sigma_floor  = false; // ตัวหารถูกยกขึ้นเป็นพื้นขั้นต่ำ
double    g_z_sma        = 0.0;   // Z แบบ SMA เดิม (แสดงเทียบ)
double    g_prev_close_zr = 0.0;  // Regression Z ของแท่งที่เพิ่งปิด
double    g_prev_close_zs = 0.0;  // SMA Z ของแท่งที่เพิ่งปิด

// --- ตัวจับช็อก / ข่าว ---
double    g_atr          = 0.0;
double    g_bar0_hi      = 0.0;
double    g_bar0_lo      = 0.0;
datetime  g_shock_until  = 0;
datetime  g_news_times[];
string    g_news_names[];
datetime  g_news_loaded  = 0;

// --- ไกยิง & ตัวกั้น ---
SideState g_sell;
SideState g_buy;
datetime  g_next_try       = 0;
datetime  g_cooldown_until = 0;   // พักหลังชน SL ขาดทุน
datetime  g_block_bar      = 0;   // แท่ง (เวลาเปิดแท่ง) ที่งดเปิดไม้เพราะตัดจบตามเวลา
string    g_last_status    = "เริ่มทำงาน";
ulong     g_activated[];          // ไม้ที่ระบบไล่จี้เริ่มทำงานแล้ว

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

//====================================================================
// 🧮 เงื่อนไข Z ตาม InpEntryLogic
//====================================================================
bool LogicHit(bool hit_r, bool hit_s) {
   if(InpEntryLogic == ENTRY_REGRESSION) return hit_r;
   if(InpEntryLogic == ENTRY_SMA)        return hit_s;
   return hit_r && hit_s;
}

// Z ที่มีผล: ทั้งคู่ = ตัวที่ใกล้ 0 กว่าเมื่อทิศเดียวกัน (ถึงเกณฑ์เมื่อทั้งคู่ถึง), ไม่งั้นตามตัวที่เลือก
double EffectiveZ(double zr, double zs) {
   if(InpEntryLogic == ENTRY_REGRESSION) return zr;
   if(InpEntryLogic == ENTRY_SMA)        return zs;
   if(zr > 0.0 && zs > 0.0) return MathMin(zr, zs);
   if(zr < 0.0 && zs < 0.0) return MathMax(zr, zs);
   return 0.0;
}

string LogicName() {
   if(InpEntryLogic == ENTRY_REGRESSION) return "Z_reg";
   if(InpEntryLogic == ENTRY_SMA)        return "Z_SMA";
   return "Z_reg + Z_SMA";
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

// ATR ของแท่ง 2..P+1 (ไม่รวมแท่งที่เพิ่งปิด เพื่อไม่ให้แท่งช็อกดันฐานตัวเอง) + เช็คแท่งที่เพิ่งปิดเป็นแท่งช็อกไหม
void UpdateAtrAndPrevShock(datetime bar0_time) {
   g_atr = 0.0;
   if(!InpUseShockFilter) return;
   int    p   = InpShockATR_Period;
   int    cnt = p + 2;
   double h[], l[], c[];
   if(CopyHigh (_Symbol, InpZ_Timeframe, 1, cnt, h) != cnt ||
      CopyLow  (_Symbol, InpZ_Timeframe, 1, cnt, l) != cnt ||
      CopyClose(_Symbol, InpZ_Timeframe, 1, cnt, c) != cnt) return;

   double sum = 0.0;
   for(int k = 1; k <= p; k++)
      sum += MathMax(h[k], c[k - 1]) - MathMin(l[k], c[k - 1]);
   g_atr = sum / p;

   double range1 = h[cnt - 1] - l[cnt - 1];
   if(g_atr > 0.0 && range1 >= InpShockATR_Mult * g_atr) {
      datetime until = bar0_time + (datetime)(InpShockBlock_Min * 60);
      if(until > g_shock_until) {
         g_shock_until = until;
         PrintFormat("⚡ แท่งที่เพิ่งปิดเป็นแท่งช็อก (ช่วงแกว่ง %.0f จุด = %.1f×ATR) → งดเข้าไม้ถึง %s",
                     PriceToPts(range1), range1 / g_atr, TimeToString(until, TIME_MINUTES));
      }
   }
}

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
   g_ref = c[n - 1];

   // 1. Regression Z ของแท่งที่เพิ่งปิด (n แท่งปิด, แท่งล่าสุดอยู่ x = n-1)
   double sy = 0.0, sxy = 0.0, syy = 0.0, sd = 0.0, sdd = 0.0;
   for(int k = 0; k < n; k++) {
      double y = c[k] - g_ref;
      sy += y; sxy += k * y; syy += y * y;
      if(k > 0) { double d = c[k] - c[k - 1]; sd += d; sdd += d * d; }
   }
   double zr, zs, fit, sig, mn, ssd;
   bool   fl;
   if(ComputeZ(sy, sxy, syy, 0.0, sd, sdd, zr, zs, fit, sig, fl, mn, ssd)) {
      g_prev_close_zr = zr;
      g_prev_close_zs = zs;
   } else {
      g_prev_close_zr = 0.0;
      g_prev_close_zs = 0.0;
   }


   // 2. แคชแท่งปิด n-1 แท่งล่าสุดสำหรับคำนวณสด (x = 0..n-2) + ส่วนต่างระหว่างแท่งปิด (n-2 ค่า)
   g_sumY = 0.0; g_sumXY = 0.0; g_sumYY = 0.0; g_sumD = 0.0; g_sumDD = 0.0;
   for(int k = 1; k < n; k++) {
      double y = c[k] - g_ref;
      int    x = k - 1;
      g_sumY += y; g_sumXY += x * y; g_sumYY += y * y;
      if(k > 1) { double d = c[k] - c[k - 1]; g_sumD += d; g_sumDD += d * d; }
   }
   g_last_close = c[n - 1];

   // 3. ATR / แท่งช็อก / ช่วงแกว่งของแท่งปัจจุบัน
   UpdateAtrAndPrevShock(t0);
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

   double n   = (double)InpZ_Period;
   double y   = bid - g_ref;
   double sy  = g_sumY  + y;
   double sxy = g_sumXY + (n - 1.0) * y;
   double syy = g_sumYY + y * y;
   double d0  = bid - g_last_close;
   double sd  = g_sumD  + d0;
   double sdd = g_sumDD + d0 * d0;

   double zr, zs, fit, sig, mn, ssd;
   bool   fl;
   if(!ComputeZ(sy, sxy, syy, y, sd, sdd, zr, zs, fit, sig, fl, mn, ssd)) return false;

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

// ตัวจับช็อกระหว่างแท่ง: ช่วงแกว่งแท่งปัจจุบัน ≥ ATR × ตัวคูณ → งดถึง X นาทีหลังแท่งนี้ปิด
void CheckShockLive() {
   if(!InpUseShockFilter || g_atr <= 0.0) return;
   double range0 = g_bar0_hi - g_bar0_lo;
   if(range0 < InpShockATR_Mult * g_atr) return;
   datetime until = g_zbar_time + (datetime)PeriodSeconds(InpZ_Timeframe) + (datetime)(InpShockBlock_Min * 60);
   if(until > g_shock_until) {
      g_shock_until = until;
      PrintFormat("⚡ แท่งปัจจุบันเป็นแท่งช็อก (ช่วงแกว่ง %.0f จุด = %.1f×ATR) → งดเข้าไม้ถึง %s",
                  PriceToPts(range0), range0 / g_atr, TimeToString(until, TIME_MINUTES));
   }
}

bool PersistBlocked(int dir) {
   if(!InpUsePersistFilter) return false;
   bool r = (dir == -1) ? (g_prev_close_zr >= InpPersistZ) : (g_prev_close_zr <= -InpPersistZ);
   bool z = (dir == -1) ? (g_prev_close_zs >= InpPersistZ) : (g_prev_close_zs <= -InpPersistZ);
   return LogicHit(r, z);
}

//====================================================================
// 📰 ปฏิทินข่าว (โหลดทุก 10 นาที, ใช้เวลาเซิร์ฟเวอร์)
//====================================================================
bool NewsEnabled() {
   return InpUseNewsCalendar && !MQLInfoInteger(MQL_TESTER);
}

void RefreshNews(datetime now) {
   if(!NewsEnabled()) return;
   if(g_news_loaded != 0 && now - g_news_loaded < 600) return;
   g_news_loaded = now;

   MqlCalendarValue vals[];
   if(!CalendarValueHistory(vals, now - (datetime)(InpNewsAfter_Min * 60), now + (datetime)DAY_SEC, NULL, InpNewsCurrency)) {
      PrintFormat("⚠️ โหลดปฏิทินข่าวไม่สำเร็จ (error %d)", GetLastError());
      return;
   }
   ArrayResize(g_news_times, 0);
   ArrayResize(g_news_names, 0);
   for(int i = 0; i < ArraySize(vals); i++) {
      MqlCalendarEvent ev;
      if(!CalendarEventById(vals[i].event_id, ev)) continue;
      if(ev.importance != CALENDAR_IMPORTANCE_HIGH) continue;
      int n = ArraySize(g_news_times);
      ArrayResize(g_news_times, n + 1);
      ArrayResize(g_news_names, n + 1);
      g_news_times[n] = vals[i].time;
      g_news_names[n] = ev.name;
   }
}

bool InNewsWindow(datetime now, string &name) {
   if(!NewsEnabled()) return false;
   for(int i = 0; i < ArraySize(g_news_times); i++) {
      datetime t = g_news_times[i];
      if(now >= t - (datetime)(InpNewsBefore_Min * 60) && now <= t + (datetime)(InpNewsAfter_Min * 60)) {
         name = g_news_names[i];
         return true;
      }
   }
   return false;
}

string NextNewsText(datetime now) {
   if(!InpUseNewsCalendar) return "";
   if(!NewsEnabled())      return "📰 ปฏิทินข่าวใช้ไม่ได้ใน Tester";
   string name;
   if(InNewsWindow(now, name)) return "📰 ช่วงข่าว: " + name;
   datetime best = 0;
   string   best_name = "";
   for(int i = 0; i < ArraySize(g_news_times); i++)
      if(g_news_times[i] > now && (best == 0 || g_news_times[i] < best)) { best = g_news_times[i]; best_name = g_news_names[i]; }
   if(best == 0) return "📰 ไม่มีข่าว High ใน 24 ชม.";
   return StringFormat("📰 ข่าวถัดไป %s (อีก %s)", best_name, FormatDuration((long)(best - now)));
}

//====================================================================
// 🎯 SIGNAL STATE MACHINE (ไกยิง → เฝ้าจุดสุดขั้ว → ยิงเมื่อถอย)
//====================================================================
void ResetSide(SideState &s) {
   s.armed      = false;
   s.in_series  = false;
   s.series_bar = 0;
   s.last_entry = 0;
   s.last_price = 0.0;
   s.count      = 0;
   s.phase      = PH_WAIT_RETREAT;
   s.ext        = 0.0;
   s.trough     = 0.0;
}

void EndSeries(SideState &s) {
   s.in_series = false;
   s.phase     = PH_WAIT_RETREAT;
}

bool SellHit() { return LogicHit(g_z_reg >= InpSellZ, g_z_sma >= InpSellZ); }
bool BuyHit()  { return LogicHit(g_z_reg <= -InpBuyZ, g_z_sma <= -InpBuyZ); }
bool SellRetreated() { return LogicHit(g_z_reg < InpSellZ - InpReArmBuffer, g_z_sma < InpSellZ - InpReArmBuffer); }
bool BuyRetreated()  { return LogicHit(g_z_reg > -InpBuyZ + InpReArmBuffer, g_z_sma > -InpBuyZ + InpReArmBuffer); }

// dir = -1 SELL (Z บวก) / 1 BUY (Z ลบ) — ใช้ g_z (Z ที่มีผลตามเงื่อนไขเข้าไม้)
void UpdateSide(SideState &st, int dir, bool retreated_arm) {
   if(st.in_series && g_zbar_time != st.series_bar) EndSeries(st);   // จำกัดไม้ซ้ำในแท่งเดียวกับไม้แรก

   if(st.in_series) {
      double z = g_z;
      double R = InpReEntryRetreatZ;
      if(st.phase == PH_WAIT_RETREAT) {
         if(dir == -1) {
            if(z > st.ext) st.ext = z;
            if(z <= st.ext - R) { st.phase = PH_WAIT_RETEST; st.trough = z; }
         } else {
            if(z < st.ext) st.ext = z;
            if(z >= st.ext + R) { st.phase = PH_WAIT_RETEST; st.trough = z; }
         }
      }
      else if(st.phase == PH_WAIT_RETEST) {
         if(dir == -1) { if(z < st.trough) st.trough = z; }
         else          { if(z > st.trough) st.trough = z; }
      }
   }
   if(!st.armed && !st.in_series && retreated_arm) st.armed = true;
}

void UpdateSides() {
   UpdateSide(g_sell, -1, SellRetreated());
   UpdateSide(g_buy,   1, BuyRetreated());
}

// 0 = ไม่มีสัญญาณ, 1 = ไม้แรกของชุด, 2 = ไม้ซ้ำแบบ Double-tap
int SideSignal(const SideState &st, bool hit, int dir, double price) {
   if(!hit) return 0;
   if(st.armed && !st.in_series) return 1;
   if(!st.in_series || st.phase != PH_WAIT_RETEST) return 0;
   if(st.count - 1 >= InpReEntryMax) return 0;

   // กระชากกลับ: ข้ามกลับจากใต้เกณฑ์ หรือดันกลับ ≥ R จากจุดที่ดีดลึกสุด
   double R = InpReEntryRetreatZ;
   bool retest = (dir == -1) ? (st.trough < InpSellZ  || g_z >= st.trough + R)
                             : (st.trough > -InpBuyZ  || g_z <= st.trough - R);
   if(!retest) return 0;

   double need = PtsToPrice(InpReEntryMinDist_Pts);   // 0 = แค่ไม่แย่กว่าไม้ก่อน
   if(dir == -1 && price < st.last_price + need) return 0;
   if(dir ==  1 && price > st.last_price - need) return 0;
   return 2;
}

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

bool LocateBlock(datetime now) {
   if(g_blk_valid && now >= g_blk_open && now < g_blk_close) return true;

   g_blk_valid = false;
   MqlDateTime dt;
   TimeToStruct(now, dt);
   datetime week_start = now - (datetime)(dt.day_of_week * DAY_SEC + dt.hour * 3600 + dt.min * 60 + dt.sec);
   long t = (long)(now - week_start);

   for(int i = 0; i < g_block_count; i++) {
      long s = g_blocks[i].s, e = g_blocks[i].e;
      if(t >= s && t < e) {
         g_blk_open  = week_start + (datetime)s;
         g_blk_close = week_start + (datetime)e;
         g_blk_valid = true;
         return true;
      }
      if(t + WEEK_SEC >= s && t + WEEK_SEC < e) {   // ช่วงที่เริ่มสัปดาห์ก่อนแล้วลากข้ามมา
         g_blk_open  = week_start + (datetime)(s - WEEK_SEC);
         g_blk_close = week_start + (datetime)(e - WEEK_SEC);
         g_blk_valid = true;
         return true;
      }
   }
   return false;
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
// 🧯 COOLDOWN หลังชน SL & งดเปิดแท่งหลังตัดจบตามเวลา
//====================================================================
// ตรวจ deal ปิดไม้: ชน SL แบบขาดทุน → ตั้งเวลาพัก / ปิดโดย EA ในแท่งปัจจุบัน → งดแท่ง (ใช้ตอนกู้สถานะ)
void InspectClosingDeal(ulong deal, bool restore_bar_block, datetime bar0) {
   if(HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagic) return;
   if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol) return;
   if(HistoryDealGetInteger(deal, DEAL_ENTRY) != DEAL_ENTRY_OUT) return;

   long     reason    = HistoryDealGetInteger(deal, DEAL_REASON);
   datetime deal_time = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);

   if(reason == DEAL_REASON_SL && InpSLCooldown_Min > 0) {
      double pnl = HistoryDealGetDouble(deal, DEAL_PROFIT) +
                   HistoryDealGetDouble(deal, DEAL_SWAP) +
                   HistoryDealGetDouble(deal, DEAL_COMMISSION);
      if(pnl < 0.0) {
         // deal ปิดฝั่ง BUY = ปิดไม้ SELL และกลับกัน → จบชุดไม้ของฝั่งนั้น
         if(HistoryDealGetInteger(deal, DEAL_TYPE) == DEAL_TYPE_BUY) EndSeries(g_sell); else EndSeries(g_buy);
         datetime until = deal_time + (datetime)(InpSLCooldown_Min * 60);
         if(until > g_cooldown_until) {
            g_cooldown_until = until;
            g_last_status    = StringFormat("ชน SL ขาดทุน → พักเข้าไม้ถึง %s", TimeToString(until, TIME_MINUTES|TIME_SECONDS));
            PrintFormat("🧯 ชน SL ขาดทุน (deal #%I64u, %.2f) → พักเข้าไม้ %d นาที", deal, pnl, InpSLCooldown_Min);
         }
      }
   }
   if(restore_bar_block && reason == DEAL_REASON_EXPERT && bar0 > 0 && deal_time >= bar0)
      g_block_bar = bar0;
}

// กู้สถานะพัก / งดแท่ง จากประวัติล่าสุดเมื่อ EA เริ่มใหม่
void RestoreGuardsFromHistory() {
   datetime now  = ServerNow();
   datetime bar0 = CurrentZBarTime();
   long     back = MathMax((long)InpSLCooldown_Min * 60, (long)PeriodSeconds(InpZ_Timeframe)) + 60;
   if(!HistorySelect(now - (datetime)back, now + 60)) return;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++) {
      ulong deal = HistoryDealGetTicket(i);
      if(deal > 0) InspectClosingDeal(deal, true, bar0);
   }
}

//====================================================================
// 💼 ORDER MANAGEMENT
//====================================================================
bool OpenOrder(int dir, double bid, double ask) {
   double lot  = NormalizeLot(InpLot);
   double sl_d = PtsToPrice(InpSL_Pts);
   double tp_d = PtsToPrice(InpTP_Pts);
   string cmt  = StringFormat("%s R%+.2f S%+.2f", InpOrderComment, g_z_reg, g_z_sma);
   bool   ok;

   if(dir == -1) ok = trade.Sell(lot, _Symbol, bid, ND(bid + sl_d), ND(bid - tp_d), cmt);
   else          ok = trade.Buy (lot, _Symbol, ask, ND(ask - sl_d), ND(ask + tp_d), cmt);

   uint rc = trade.ResultRetcode();
   if(ok && (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_PLACED || rc == TRADE_RETCODE_DONE_PARTIAL)) {
      PrintFormat("✅ เปิด %s %.2f lot @ %s | Z_reg %+.2f / Z_SMA %+.2f", (dir == -1 ? "SELL" : "BUY"), lot,
                  DoubleToString(trade.ResultPrice(), _Digits), g_z_reg, g_z_sma);
      return true;
   }
   PrintFormat("❌ เปิด %s ไม่สำเร็จ: %u %s", (dir == -1 ? "SELL" : "BUY"), rc, trade.ResultRetcodeDescription());
   return false;
}

void OnSeriesEntry(SideState &st, int kind, datetime now, double fill) {
   if(kind == 1) {
      st.armed      = false;
      st.in_series  = true;
      st.series_bar = g_zbar_time;
      st.count      = 0;
   }
   st.count++;
   st.last_entry = now;
   st.last_price = fill;
   st.phase      = PH_WAIT_RETREAT;
   st.ext        = g_z;
   st.trough     = g_z;
}

void TryEntries(int ts, double bid, double ask) {
   datetime now = ServerNow();
   int sig_sell = SideSignal(g_sell, SellHit(), -1, bid);
   int sig_buy  = SideSignal(g_buy,  BuyHit(),   1, ask);
   if(sig_sell == 0 && sig_buy == 0) return;

   int    dir  = (sig_sell > 0) ? -1 : 1;
   int    kind = (dir == -1) ? sig_sell : sig_buy;
   string side = ((dir == -1) ? "SELL" : "BUY") + (kind == 2 ? " (ไม้ซ้ำ)" : "");

   if(ts != TS_OPEN) { g_last_status = side + " ผ่านเงื่อนไข แต่ติดช่วงเวลาห้ามเข้า"; return; }
   if(now < g_cooldown_until) {
      g_last_status = side + " ผ่านเงื่อนไข แต่อยู่ในช่วงพักหลังชน SL (อีก " + FormatDuration((long)(g_cooldown_until - now)) + ")";
      return;
   }
   if(g_block_bar != 0 && g_block_bar == g_zbar_time) {
      g_last_status = side + " ผ่านเงื่อนไข แต่งดเปิดแท่งนี้ (เพิ่งตัดจบตามเวลา)";
      return;
   }
   if(now < g_shock_until) {
      g_last_status = side + " ผ่านเงื่อนไข แต่ติดตัวจับช็อก (อีก " + FormatDuration((long)(g_shock_until - now)) + ")";
      return;
   }
   string news_name;
   if(InNewsWindow(now, news_name)) {
      g_last_status = side + " ผ่านเงื่อนไข แต่อยู่ในช่วงข่าว: " + news_name;
      return;
   }
   if(PersistBlocked(dir)) {
      g_last_status = StringFormat("%s ผ่านเงื่อนไข แต่แท่งก่อนหน้าปิดค้างโซนสุดขั้ว (R %+.2f / S %+.2f)", side, g_prev_close_zr, g_prev_close_zs);
      return;
   }
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED)) {
      g_last_status = side + " ผ่านเงื่อนไข แต่ปิด Algo Trading อยู่";
      return;
   }
   double spread_pts = PriceToPts(ask - bid);
   if(spread_pts > InpMaxSpread_Pts) {
      g_last_status = StringFormat("%s ผ่านเงื่อนไข แต่สเปรด %.0f > %.0f จุด", side, spread_pts, InpMaxSpread_Pts);
      return;
   }
   if(now < g_next_try) return;

   int buys, sells;
   CountPositions(buys, sells);
   if(buys + sells >= InpMaxPositions) {
      g_last_status = StringFormat("%s ผ่านเงื่อนไข แต่ครบ %d ไม้แล้ว", side, InpMaxPositions);
      return;
   }
   if((dir == -1 && buys > 0) || (dir == 1 && sells > 0)) {
      g_last_status = side + " ผ่านเงื่อนไข แต่มีไม้ฝั่งตรงข้ามค้างอยู่";
      return;
   }

   if(OpenOrder(dir, bid, ask)) {
      double fill = trade.ResultPrice();
      if(fill <= 0.0) fill = (dir == -1) ? bid : ask;
      if(dir == -1) OnSeriesEntry(g_sell, kind, now, fill);
      else          OnSeriesEntry(g_buy,  kind, now, fill);
      g_last_status = StringFormat("เปิด %s ที่ Z_reg %+.2f / Z_SMA %+.2f", side, g_z_reg, g_z_sma);
   } else {
      g_next_try    = now + 1;   // กันยิงคำสั่งรัว ๆ เมื่อโบรกปฏิเสธ
      g_last_status = side + " ส่งคำสั่งไม่สำเร็จ: " + trade.ResultRetcodeDescription();
   }
}

void CloseAllPositions() {
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
         if(prof >= start) {
            // กำไรถึงจุดเริ่มไล่จี้ → เปิดระบบไล่จี้ทันที (ไม่รอรอบ 5 วินาที)
            MarkActivated(ticket);
            PrintFormat("🔥 #%I64u เริ่มไล่จี้ (กำไร %.0f จุด หลังเปิด %d วินาที)", ticket, PriceToPts(prof), (int)(now - opened));
            TrailPosition(ticket, is_buy, sl, tp, bid, ask, dist, stops, freeze);
         }
         else if(InpQuickWindow_Sec > 0 && now - opened >= InpQuickWindow_Sec) {
            // ครบเวลาแล้วไม่ดีดกลับ → ตัดจบ + งดเปิดไม้ทั้งแท่งนี้
            if(trade.PositionClose(ticket)) {
               g_block_bar   = CurrentZBarTime();
               if(is_buy) EndSeries(g_buy); else EndSeries(g_sell);   // ไม่ดีดกลับ = สมมติฐานล้ม
               g_last_status = StringFormat("ตัดจบ #%I64u (ไม่ดีดกลับใน %d วินาที, %+.0f จุด) → งดเปิดแท่งนี้",
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
      if(side == 0) { hit_r = zr[0] >= InpSellZ;  hit_s = zs[0] >= InpSellZ; }
      else          { hit_r = zr[1] <= -InpBuyZ;  hit_s = zs[1] <= -InpBuyZ; }
      bool show = ok[side] && (hit_r || hit_s);
      if(!show) { if(ObjectFind(0, name) >= 0) ObjectDelete(0, name); continue; }

      bool  hit_active = LogicHit(hit_r, hit_s);
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
                      StringFormat("%s | ที่ %s: Z_reg %+.2f%s / Z_SMA %+.2f%s | เงื่อนไข %s: %s",
                                   TimeToString(t, TIME_DATE|TIME_MINUTES), (side == 0 ? "High" : "Low"),
                                   zr[side], (hit_r ? " ✓" : ""), zs[side], (hit_s ? " ✓" : ""),
                                   LogicName(), (hit_active ? "ผ่าน" : "ไม่ครบ")));
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
   double n  = (double)InpZ_Period;
   double zr[2], zs[2], px[2];
   bool   ok[2];
   px[0] = g_bar0_hi;
   px[1] = g_bar0_lo;
   for(int s = 0; s < 2; s++) {
      double y   = px[s] - g_ref;
      double d0  = px[s] - g_last_close;
      double fit, sig, mn, ssd;
      bool   fl;
      zr[s] = 0.0; zs[s] = 0.0;
      ok[s] = (px[s] > 0.0) && ComputeZ(g_sumY + y, g_sumXY + (n - 1.0) * y, g_sumYY + y * y, y,
                                        g_sumD + d0, g_sumDD + d0 * d0, zr[s], zs[s], fit, sig, fl, mn, ssd);
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

// สีป้าย Z ตามโซน: ถึงเกณฑ์ = แดงส้ม/ฟ้า, ใกล้เกณฑ์ (เลยระดับ re-arm) = ทอง, ปกติ = เงิน
color LiveZColor(double z) {
   if(z >= InpSellZ)                   return InpClrLiveSell;
   if(z <= -InpBuyZ)                   return InpClrLiveBuy;
   if(z >= InpSellZ - InpReArmBuffer ||
      z <= -InpBuyZ + InpReArmBuffer)  return InpClrLiveNear;
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
   if(g_sell.in_series)      text = "SELL " + SeriesShortText(g_sell, true)  + "  |  " + text;
   else if(g_buy.in_series)  text = "BUY "  + SeriesShortText(g_buy,  false) + "  |  " + text;

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
                   StringFormat("Z_reg %+.3f (กลาง %s) | Z_SMA %+.3f (SMA20 %s) | เงื่อนไขเข้าไม้: %s",
                                g_z_reg, DoubleToString(g_center, _Digits), g_z_sma, DoubleToString(g_sma_mean, _Digits),
                                LogicName()));

   g_live_z_text = text;
   g_live_z_y    = y;
}

void UpdateZLines() {
   if(!g_draw || !g_z_valid) return;
   string tag_r = (InpEntryLogic != ENTRY_SMA)        ? " (ใช้เทรด)" : " (เทียบ)";
   string tag_s = (InpEntryLogic != ENTRY_REGRESSION) ? " (ใช้เทรด)" : " (เทียบ)";

   if(InpShowZLines) {
      MoveHLine(LINE_MAIN, g_center,                     InpClrZCenter,   STYLE_DOT,  1, "[Regression] เส้นกลาง Z = 0" + tag_r, g_line_main);
      MoveHLine(LINE_SELL, g_center + InpSellZ * g_sigma, InpClrZSellLine, STYLE_DASH, 1, StringFormat("[Regression] SELL Z ≥ +%.2f", InpSellZ) + tag_r, g_line_sell);
      MoveHLine(LINE_BUY,  g_center - InpBuyZ  * g_sigma, InpClrZBuyLine,  STYLE_DASH, 1, StringFormat("[Regression] BUY Z ≤ −%.2f", InpBuyZ) + tag_r,  g_line_buy);
   }
   if(InpShowSmaZLines) {
      MoveHLine(LINE_SMA_MAIN, g_sma_mean,                      InpClrSmaCenter,   STYLE_DOT,     1, "[SMA20] เส้นกลาง Z = 0" + tag_s, g_line_sma_main);
      MoveHLine(LINE_SMA_SELL, g_sma_mean + InpSellZ * g_sma_sd, InpClrSmaSellLine, STYLE_DASHDOT, 1, StringFormat("[SMA20] SELL Z ≥ +%.2f", InpSellZ) + tag_s, g_line_sma_sell);
      MoveHLine(LINE_SMA_BUY,  g_sma_mean - InpBuyZ  * g_sma_sd, InpClrSmaBuyLine,  STYLE_DASHDOT, 1, StringFormat("[SMA20] BUY Z ≤ −%.2f", InpBuyZ) + tag_s,  g_line_sma_buy);
   }
}

string SeriesShortText(const SideState &s, bool is_sell) {
   int total = 1 + InpReEntryMax;
   if(s.count >= total) return StringFormat("ชุด %d/%d ครบ", s.count, total);
   if(s.phase == PH_WAIT_RETREAT)
      return StringFormat("ชุด %d/%d รอดีด %s %+.2f", s.count, total, (is_sell ? "≤" : "≥"),
                          (is_sell ? s.ext - InpReEntryRetreatZ : s.ext + InpReEntryRetreatZ));
   return StringFormat("ชุด %d/%d ดีดแล้ว รอกระชากกลับ", s.count, total);
}

string SideText(const SideState &s, bool is_sell) {
   if(s.in_series) {
      int total = 1 + InpReEntryMax;
      if(s.count >= total)
         return StringFormat("🔁 ชุดไม้ครบ %d/%d — รอจบแท่ง", s.count, total);
      if(s.phase == PH_WAIT_RETREAT)
         return StringFormat("🔁 ชุดไม้ %d/%d | สุดขั้ว %+.2f → รอดีดกลับถึง %s %+.2f", s.count, total, s.ext,
                             (is_sell ? "≤" : "≥"), (is_sell ? s.ext - InpReEntryRetreatZ : s.ext + InpReEntryRetreatZ));
      double target = is_sell ? MathMin(InpSellZ, s.trough + InpReEntryRetreatZ)
                              : MathMax(-InpBuyZ, s.trough - InpReEntryRetreatZ);
      return StringFormat("🔁 ชุดไม้ %d/%d | ดีดแล้ว (ลึกสุด %+.2f) → รอกระชากกลับ %s %+.2f + เกณฑ์ครบ + ราคา %s %s",
                          s.count, total, s.trough, (is_sell ? "≥" : "≤"), target,
                          (is_sell ? "≥" : "≤"), DoubleToString(s.last_price, _Digits));
   }
   if(s.armed)
      return StringFormat("✅ พร้อม รอ %s %s %+.2f", LogicName(), (is_sell ? "≥" : "≤"), (is_sell ? InpSellZ : -InpBuyZ));
   return StringFormat("⏳ ปลดไก รอ %s %s %+.2f", LogicName(), (is_sell ? "<" : ">"),
                       (is_sell ? InpSellZ - InpReArmBuffer : -InpBuyZ + InpReArmBuffer));
}

string GuardText(datetime now) {
   string out = "";
   if(now < g_cooldown_until) out += "🧯 พักหลังชน SL อีก " + FormatDuration((long)(g_cooldown_until - now));
   if(g_block_bar != 0 && g_block_bar == CurrentZBarTime()) {
      if(out != "") out += " | ";
      out += "⛔ งดเปิดแท่งนี้ (ตัดจบตามเวลา)";
   }
   if(now < g_shock_until) {
      if(out != "") out += " | ";
      out += "⚡ ช็อก อีก " + FormatDuration((long)(g_shock_until - now));
   }
   if(InpUsePersistFilter && (PersistBlocked(-1) || PersistBlocked(1))) {
      if(out != "") out += " | ";
      out += StringFormat("🧱 แท่งก่อนปิดค้างโซน (R %+.2f / S %+.2f) งดฝั่ง %s",
                          g_prev_close_zr, g_prev_close_zs, (PersistBlocked(-1) ? "SELL" : "BUY"));
   }
   return (out == "") ? "ไม่มี" : out;
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
      else if(InpQuickWindow_Sec > 0) {
         long left = (long)InpQuickWindow_Sec - (long)(now - opened);
         if(left < 0) left = 0;
         st = StringFormat("⏱️ เหลือ %d วิ ต้องกำไรถึง %.0f", (int)left, InpTrailStart_Pts);
      }
      else
         st = StringFormat("รอกำไรถึง %.0f", InpTrailStart_Pts);

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

   string mode_r = (InpEntryLogic != ENTRY_SMA)        ? "▶" : " ";
   string mode_s = (InpEntryLogic != ENTRY_REGRESSION) ? "▶" : " ";
   string z_str = g_z_valid
      ? StringFormat("%sZ_reg %+.2f (กลาง %s, σ %.0f จุด%s)  vs  %sZ_SMA %+.2f (SMA20 %s, σ %.0f จุด) | ต่าง %+.2f",
                     mode_r, g_z_reg, DoubleToString(g_center, _Digits), PriceToPts(g_sigma), (g_sigma_floor ? " พื้น" : ""),
                     mode_s, g_z_sma, DoubleToString(g_sma_mean, _Digits), PriceToPts(g_sma_sd), g_z_reg - g_z_sma)
      : "รอข้อมูลแท่งเทียน...";
   string atr_str = (InpUseShockFilter && g_atr > 0.0)
                    ? StringFormat("ATR%d %.0f จุด | ช่วงแกว่งแท่งนี้ %.1f×ATR (ช็อกที่ %.1f×)",
                                   InpShockATR_Period, PriceToPts(g_atr), (g_bar0_hi - g_bar0_lo) / g_atr, InpShockATR_Mult)
                    : "ตัวจับช็อกปิดอยู่";
   string news_str = NextNewsText(now);

   string msg = StringFormat("=== 📊 7-Lines Counter EA v6.00 (เข้าไม้: %s | ไม้ซ้ำ Double-tap ≤ %d) ===\n", LogicName(), InpReEntryMax);
   msg += StringFormat("Z (%s, %d) : %s\n", EnumToString(InpZ_Timeframe), InpZ_Period, z_str);
   msg += StringFormat("Z แท่งที่เพิ่งปิด : R %+.2f / S %+.2f | %s%s\n", g_prev_close_zr, g_prev_close_zs, atr_str, (news_str == "" ? "" : " | " + news_str));
   msg += StringFormat("SELL (≥ +%.2f) : %s\n", InpSellZ, SideText(g_sell, true));
   msg += StringFormat("BUY  (≤ −%.2f) : %s\n", InpBuyZ,  SideText(g_buy,  false));
   msg += StringFormat("ออเดอร์ : BUY %d / SELL %d (รวม %d/%d) | สเปรด %.0f / %.0f จุด\n",
                       buys, sells, buys + sells, InpMaxPositions, PriceToPts(ask - bid), InpMaxSpread_Pts);
   msg += "ตัวกั้น : " + GuardText(now) + "\n";
   msg += "เวลาตลาด : " + TimeStateText(ts, now) + "\n";
   if(InpShow7Lines) msg += "เส้น 7 เส้น : " + g_lines_status + "\n";
   msg += "สถานะล่าสุด : " + g_last_status;
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
   if(InpBarZBars < 1 || InpBarZBars > 5000) { Print("❌ InpBarZBars ต้องอยู่ระหว่าง 1-5000"); return(INIT_PARAMETERS_INCORRECT); }
   if(InpSellZ <= 0.0 || InpBuyZ <= 0.0 || InpReArmBuffer < 0.0 || InpReEntryRetreatZ <= 0.0 ||
      InpReEntryMax < 0 || InpReEntryMinDist_Pts < 0.0) {
      Print("❌ ค่า Z ไม่ถูกต้อง");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpLot <= 0.0 || InpMaxPositions < 1) { Print("❌ Lot / จำนวนไม้ไม่ถูกต้อง"); return(INIT_PARAMETERS_INCORRECT); }
   if(InpTP_Pts <= 0.0 || InpSL_Pts <= 0.0 || InpTrailDist_Pts <= 0.0 || InpTrailInterval_Sec < 1) {
      Print("❌ TP / SL / ระยะโล่ / รอบไล่จี้ ไม่ถูกต้อง");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpQuickWindow_Sec < 0 || InpSLCooldown_Min < 0) {
      Print("❌ เวลาตัดจบ / เวลาพัก ต้องไม่ติดลบ");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpSigmaFloorMult < 0.0 || InpShockATR_Period < 1 || InpShockATR_Mult <= 0.0 || InpShockBlock_Min < 0 ||
      InpPersistZ <= 0.0 || InpNewsBefore_Min < 0 || InpNewsAfter_Min < 0) {
      Print("❌ ค่าตัวกรองข่าว / ช็อก / ความต่อเนื่อง / พื้นตัวหาร ไม่ถูกต้อง");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpUseNewsCalendar && MQLInfoInteger(MQL_TESTER))
      Print("ℹ️ ปฏิทินข่าวใช้ไม่ได้ใน Strategy Tester — ใช้เฉพาะตัวจับช็อกและกรองความต่อเนื่อง");
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

   // เริ่มต้นแบบปลดไก: ต้องรอ Z ถอยกลับก่อนจึงเฝ้าได้ (กันเข้ากลางทางเมื่อเปิด EA ตอน Z เกินเกณฑ์อยู่แล้ว)
   ResetSide(g_sell);
   ResetSide(g_buy);
   g_zbar_time      = 0;
   g_z_ready        = false;
   g_blk_valid      = false;
   g_last_trail     = 0;
   g_next_try       = 0;
   g_cooldown_until = 0;
   g_block_bar      = 0;
   g_shock_until    = 0;
   g_news_loaded    = 0;
   g_atr            = 0.0;
   g_prev_close_zr  = 0.0;
   g_prev_close_zs  = 0.0;
   ArrayResize(g_seg_times, 0);
   ArrayResize(g_marks, 0);
   g_marks_bar = 0;
   ArrayResize(g_news_times, 0);
   ArrayResize(g_news_names, 0);
   g_last_comment   = "";
   g_line_main = g_line_sell = g_line_buy = 0.0;
   g_line_sma_main = g_line_sma_sell = g_line_sma_buy = 0.0;
   g_live_z_text = ""; g_live_z_y = -1;
   g_lines_status = "ยังไม่ได้วาด";
   ArrayResize(g_activated, 0);

   RestoreGuardsFromHistory();
   RefreshNews(ServerNow());

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
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= 0.0) return;
   if(!UpdateZ(bid)) return;

   CheckShockLive();
   UpdateSides();
   UpdateLiveZLabel(bid);

   int ts = GetTimeState(ServerNow());
   if(ts == TS_CLOSING) {
      CloseAllPositions();
      return;
   }
   TryEntries(ts, bid, ask);
}

void OnTimer() {
   datetime now = ServerNow();
   int ts = GetTimeState(now);
   RefreshNews(now);

   // 1. บังคับปิดก่อนตลาดปิดสัปดาห์ / จัดการไม้ (เปิดไล่จี้, ตัดจบตามเวลา, ขยับโล่)
   if(ts == TS_CLOSING)     CloseAllPositions();
   else if(ts != TS_CLOSED) ManagePositions(now);

   // 2. อัปเดตการแสดงผล (Z คำนวณจาก Bid ล่าสุด ไม่กระทบสถานะไกยิง)
   if(g_draw) {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(bid > 0.0) UpdateZ(bid);
      UpdateZLines();
      UpdateLinesLive();
      UpdateBarZLabels();
      UpdateEntryMarks();
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
   InspectClosingDeal(trans.deal, false, 0);
   AddEntryMarkFromDeal(trans.deal);
}
//+------------------------------------------------------------------+
