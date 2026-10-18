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
// 🆕 v8.00: ไม้ลูกโซ่ + โหมดตามน้ำแท่งข่าว
//  • ตัวกรองเหลือแค่: เวลาตลาดเปิด/ปิดรายสัปดาห์ + เพดานสเปรด (เอาตัวจับช็อก / ความต่อเนื่อง / งดข่าว ออก)
//  • เปิดไม้ได้หลังแท่ง (TF ของ Z) เปิดแล้ว InpBarStartDelay_Sec วินาที — นาทีแรกไม่เฝ้า Z
//  • TP 30,000 / SL 2,500 / ไล่จี้เริ่ม 10,000 ห่าง 8,000 (ทุกไม้)
//  • ไม้ลูกโซ่ (ช่วงปกติ): C1 = สวนกลับด้วย Z วิกฤต + จับเวลา 3 วิ (Lot เริ่มต้น)
//      C2 = Limit สวนกลับ เลย SL ของ C1 ไป 1,000 จุด (Lot +0.01)
//      C3 = Limit สวนกลับ เลย SL ของ C2 ไป 500 จุด (Lot +0.02)
//      C4 = ถ้า C3 ชน SL → เปิดตามน้ำทันที (Lot +0.03)
//      Limit หมดอายุเมื่อไม้ก่อนหน้าเริ่มไล่จี้ / ครบ 30 นาที / เข้าแท่งข่าว; ไม้ในชุดจบแบบไม่ใช่ SL → จบชุด
//  • แท่งข่าว USD High: ปิดระบบสวนกลับเฉพาะแท่งนั้น → ตามน้ำเมื่อ |Z| ≥ 2.0 (1 ไม้/แท่ง, ไม่มี TP, ไม่ตัด 60 วิ, ใช้ไล่จี้)
//  • Tick Replay จำลองทั้งลูกโซ่ (Limit fill / C4) และโหมดข่าว + สรุปผลเป็น $ ตาม Lot
//
// 🆕 v7.00: จับเวลา No new high/low + Tick Replay
//  • ไม้แรก: Z ถึงเกณฑ์ (ตาม InpEntryLogic) → เริ่มเฝ้า: จำค่าสุดขั้วของ Z_reg และ Z_SMA
//    ถ้า Z ตัวใดทำค่าสุดขั้วใหม่ (เกิน InpNoNewExtEps) → นับเวลาใหม่, ครบ InpNoNewExt_Sec วินาที → ยิง
//    (ระหว่างนับ Z หลุดเกณฑ์ก็ยังยิง เพราะเคยผ่านแล้ว) — ขึ้นแท่งใหม่ปรับค่าอ้างอิงโดยไม่นับเป็นค่าใหม่
//  • ตอนยิง ถ้าติดตัวกรอง (เวลา/ช็อก/ข่าว/ความต่อเนื่อง/สเปรด) → ทิ้งสัญญาณนั้น แล้วเริ่มเฝ้าใหม่ถ้า Z ยังถึงเกณฑ์
//  • ยกเลิก: ไม้ซ้ำ, ไกยิง/ถอยกลับ 0.5, พักหลังชน SL, งดแท่งหลังตัด 60 วิ — เปิดได้ครั้งละ 1 ไม้
//    ไม้ปิดแล้ว (TP/SL/ตัด/โล่) เปิดใหม่ได้ทันทีถ้าเงื่อนไขผ่าน
//  • Tick Replay: ดึง tick จริงย้อนหลัง InpReplayDays วัน เดินด้วยกติกาเดียวกับ EA (เฝ้า/ตัวกรอง/TP/SL/โล่/ตัด 60 วิ/ปิดสุดสัปดาห์)
//    → มาร์กไม้จำลองพร้อมผล + มาร์กสัญญาณที่ถูกตัวกรองทิ้ง + สรุปผลบน Dashboard, แล้วเดินต่อแบบสดทุกวินาที
//  • ป้าย Z บนแท่งตั้งได้ถึง 20,000 แท่ง (ย้อนหลังคำนวณครั้งเดียว + ต่อเฉพาะแท่งใหม่)
//
// 🆕 v6.10: ย้อนหลังบนกราฟ (จุดเข้าจำลองจาก OHLC ถูกแทนด้วย Tick Replay ใน v7.00)
//  • จุดเข้าไม้แรก "จำลอง" ย้อนหลัง (ประมาณจาก OHLC ของ TF ของ Z): ถึงเกณฑ์ตามเงื่อนไข + ไกยิง (ต้องถอยกลับก่อน)
//    + กรองความต่อเนื่อง + ตัวจับช็อก + เวลาตลาด — ราคาเข้าหาด้วย bisection หาราคาแรกที่ Z ถึงเกณฑ์
//    (ไม่จำลองไม้ซ้ำ / พักหลัง SL / ตัด 60 วินาที / เพดานไม้ เพราะต้องรู้ลำดับราคาในแท่ง)
//  • ช่วงข่าวย้อนหลัง: เส้นแนวตั้งเวลาข่าว + แถบช่วงงดเทรด (ก่อน/หลัง) จากปฏิทิน MT5 (ใช้ไม่ได้ใน Tester)
//
// 🆕 v6.00: ไม้ซ้ำแบบ Double-tap (แทนการนับเวลา 10 วินาที) — ยกเลิกใน v7.00
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
// 📋 ตรรกะการเข้าไม้ (v8.00)
//  แท่งปกติ: ไม่มีไม้/ชุดค้าง + เลยนาทีแรก ──(Z ถึงเกณฑ์)──► เฝ้าค่าสุดขั้ว ──(ไม่มีค่าใหม่ 3 วิ)──► C1 → ลูกโซ่ C2/C3/C4
//  แท่งข่าว: เลยนาทีแรก + ไม่มีไม้ค้าง ──(|Z| ≥ 2.0)──► ตามน้ำ 1 ไม้
//  • ตัวกรอง: เวลาตลาด + สเปรด
//
// 📋 ตรรกะการจัดการไม้
//  • TP / SL คงที่ตั้งแต่เปิดไม้
//  • ภายใน QuickWindow วินาทีแรก ตรวจทุก 1 วินาที: กำไรถึงจุดเริ่มไล่จี้ → เปิดระบบไล่จี้ทันที
//  • ครบ QuickWindow แล้วระบบไล่จี้ยังไม่ทำงาน → ตัดจบ
//  • หลังเปิดระบบไล่จี้ ขยับโล่ทุก TrailInterval วินาที (ทางเดียว)
//  • ห้ามเข้า 1 ชม.แรกหลังตลาดเปิดสัปดาห์ / ปิดทุกไม้ 30 นาทีก่อนตลาดปิดสัปดาห์
//
// ⚡ การประหยัด CPU
//  • Z: แคช Σy, Σxy, Σy² ของแท่งที่ปิดแล้ว + ATR คำนวณเฉพาะตอนขึ้นแท่งใหม่ (ต่อ Tick ไม่กี่บรรทัดคณิต)
//  • จัดการไม้ / Dashboard / เส้น ทำบน OnTimer 1 วินาที, ตรวจ SL ผ่าน OnTradeTransaction (ไม่ไล่ประวัติ)
//  • Dashboard เขียนเฉพาะเมื่อข้อความเปลี่ยน, ไม่วาดอะไรใน Tester แบบไม่เปิด Visual
//
#property copyright   "Commander's Quant System"
#property version     "8.00"
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
input int             InpNoNewExt_Sec      = 3;          // ยิงเมื่อ Z ทั้งสองไม่ทำค่าสุดขั้วใหม่ครบกี่วินาที
input double          InpNoNewExtEps       = 0.01;       // Z ต้องเกินค่าสุดขั้วเดิมเท่านี้ถึงนับเป็นค่าใหม่
input double          InpSigmaFloorMult    = 0.50;       // ตัวหาร Z ต้องไม่น้อยกว่า ค่านี้ × StdDev ของการเปลี่ยนแปลงราคาต่อแท่ง

input group "=== 2. ออเดอร์ ==="
input double          InpLot               = 0.01;       // Lot คงที่ต่อไม้
input double          InpTP_Pts            = 30000.0;    // Take Profit (จุด)
input double          InpSL_Pts            = 2500.0;     // Stop Loss (จุด)
input double          InpSlippage_Pts      = 300.0;      // Slippage สูงสุดตอนส่งคำสั่ง (จุด)
input long            InpMagic             = 880100;     // Magic Number
input string          InpOrderComment      = "7L-CNT";   // คอมเมนต์ออเดอร์

input group "=== 3. ไล่จี้กำไร ==="
input double          InpTrailStart_Pts    = 10000.0;    // เริ่มไล่จี้เมื่อกำไรถึง (จุด)
input double          InpTrailDist_Pts     = 8000.0;     // ระยะโล่ห่างจากราคา (จุด)
input int             InpTrailInterval_Sec = 5;          // ขยับโล่ทุกกี่วินาที (หลังเริ่มไล่จี้แล้ว)

input group "=== 4. กฎดีดกลับเร็ว ==="
input int             InpQuickWindow_Sec   = 60;         // ไม้สวนกลับ (C1-C4) ต้องเข้าระบบไล่จี้ภายในกี่วินาที ไม่งั้นตัดจบ (0 = ปิด)
input int             InpBarStartDelay_Sec = 60;         // เปิดไม้ได้หลังแท่ง (TF ของ Z) เปิดแล้วกี่วินาที

input group "=== 5. ไม้ลูกโซ่ (ช่วงปกติ) ==="
input bool            InpChainEnable       = true;       // เปิดระบบไม้ลูกโซ่ C2 / C3 / C4
input double          InpChainGap2_Pts     = 1000.0;     // C2: Limit เลย SL ของ C1 ไปกี่จุด
input double          InpChainGap3_Pts     = 500.0;      // C3: Limit เลย SL ของ C2 ไปกี่จุด
input double          InpChainLotStep      = 0.01;       // Lot เพิ่มต่อลำดับไม้ (C2 = Lot+step, C3 = Lot+2·step, ...)
input int             InpChainLimitLife_Min = 30;        // อายุ Limit (นาที) — ยกเลิกก่อนถ้าไม้ก่อนหน้าเริ่มไล่จี้
input bool            InpChainTrendLast    = true;       // C4: C3 ชน SL → เปิดตามน้ำทันที

input group "=== 6. แท่งข่าว (ตามน้ำ) ==="
input bool            InpUseNewsTrend      = true;       // แท่งที่มีข่าว USD High: ปิดสวนกลับ → ตามน้ำ (ใช้ไม่ได้ใน Tester)
input string          InpNewsCurrency      = "USD";      // สกุลเงินของข่าว
input double          InpNewsTrendZ        = 2.0;        // ตามน้ำเมื่อ |Z| ≥ ค่านี้ (ตาม InpEntryLogic)
input double          InpNewsSL_Pts        = 2500.0;     // SL ไม้ข่าว (จุด, 0 = ไม่มี SL) — ไม่มี TP, ใช้ไล่จี้

input group "=== 7. ตัวกรองทั่วไป ==="
input double          InpMaxSpread_Pts     = 800.0;      // สเปรดสูงสุดที่ยอมให้เข้าไม้ (จุด)
input int             InpNoTradeAfterOpen_Min = 60;      // ห้ามเข้าไม้หลังตลาดเปิดสัปดาห์ (นาที)
input int             InpCloseBeforeClose_Min = 30;      // ปิดทุกไม้ก่อนตลาดปิดสัปดาห์ (นาที)

input group "=== 8. การแสดงผล ==="
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
input int             InpBarZBars          = 2000;       // จำนวนแท่งย้อนหลัง (TF ของ Z) ที่แสดงป้าย (สูงสุด 20,000)
input int             InpBarZFontSize      = 8;          // ขนาดตัวอักษรป้าย Z บนแท่ง
input double          InpBarZOffset_Pts    = 300.0;      // ระยะห่างป้ายจากไส้เทียน (จุด)
input bool            InpShowEntryMarks    = true;       // มาร์กจุดเปิดไม้ + ระยะห่างถึงปลายไส้เทียน
input bool            InpShowReplay        = true;       // Tick Replay: จำลองไม้ย้อนหลังจาก tick จริง + ผลแต่ละไม้
input int             InpReplayDays        = 10;         // Tick Replay: ย้อนหลังกี่วัน (1-60)
input bool            InpShowReplayBlocked = true;       // Tick Replay: มาร์กสัญญาณที่ถูกตัวกรองทิ้ง
input bool            InpShowNewsHistory   = true;       // แสดงช่วงข่าวบนกราฟ (ย้อนหลัง + 24 ชม.ข้างหน้า)
input bool            InpNewsIncludeMedium = false;      // แสดงข่าวระดับ Medium ด้วย (การงดเทรดยังใช้เฉพาะ High)

input group "=== 9. สี ==="
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
input color           InpClrNewsLine       = clrMediumPurple;   // เส้นเวลาข่าว
input color           InpClrNewsZone       = C'45,35,70';       // แถบแท่งข่าว (โหมดตามน้ำ)

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
   double ext_r;      // ค่าสุดขั้วของ Z_reg ระหว่างเฝ้า
   double ext_s;      // ค่าสุดขั้วของ Z_SMA ระหว่างเฝ้า
   long   last_new;   // เวลา (msc) ที่ทำค่าสุดขั้วใหม่ล่าสุด
   long   started;    // เวลา (msc) ที่เริ่มเฝ้า
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

// --- ช่วงแกว่งแท่งปัจจุบัน / ข่าว ---
double    g_bar0_hi      = 0.0;
double    g_bar0_lo      = 0.0;
datetime  g_news_times[];
string    g_news_names[];
datetime  g_news_loaded  = 0;

// --- เฝ้าค่าสุดขั้ว & ตัวกั้น ---
WatchState g_wsell;
WatchState g_wbuy;
bool      g_bar_changed    = false;   // ขึ้นแท่งใหม่ (TF ของ Z) ใน UpdateZ ล่าสุด
long      g_last_tick_msc  = 0;
datetime  g_next_try       = 0;
string    g_last_status    = "เริ่มทำงาน";
ulong     g_activated[];          // ไม้ที่ระบบไล่จี้เริ่มทำงานแล้ว

// --- ไม้ลูกโซ่ (EA จริง) ---
struct ChainState {
   bool     active;
   int      dir;          // ทิศสวนกลับของชุด (-1 SELL / 1 BUY)
   int      stage;        // ไม้ปัจจุบัน 1..4
   ulong    pos;          // ticket ไม้ที่ถืออยู่ (0 = ไม่มี)
   ulong    pend;         // ticket Limit ที่รออยู่ (0 = ไม่มี)
   int      pend_stage;
   double   pend_price;
   datetime pend_time;
   bool     next_done;    // วาง/ยกเลิก Limit ของไม้ถัดไปแล้ว (ไม่วางซ้ำ)
};
ChainState g_ch;
datetime   g_news_traded_bar = 0;   // แท่งข่าวที่เปิดไม้ตามน้ำไปแล้ว

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
   g_sumY          = g_zc.sY;  g_sumXY = g_zc.sXY; g_sumYY = g_zc.sYY;
   g_sumD          = g_zc.sD;  g_sumDD = g_zc.sDD;
   g_last_close    = g_zc.last_close;
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
   return InpUseNewsTrend && !MQLInfoInteger(MQL_TESTER);
}

// โหลดข่าว High ของสกุลที่เลือก ครอบช่วง Tick Replay + 24 ชม.ข้างหน้า (ทุก 10 นาที)
void RefreshNews(datetime now) {
   if(!NewsEnabled()) return;
   if(g_news_loaded != 0 && now - g_news_loaded < 600) return;
   g_news_loaded = now;

   MqlCalendarValue vals[];
   long back = (InpShowReplay ? (long)InpReplayDays * DAY_SEC : 0) + DAY_SEC;
   if(!CalendarValueHistory(vals, now - (datetime)back, now + (datetime)DAY_SEC, NULL, InpNewsCurrency)) {
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

// แท่ง (TF ของ Z) ที่เริ่มเวลา bar_t มีข่าวออกในแท่งไหม
bool IsNewsBar(datetime bar_t, string &name) {
   if(!NewsEnabled() || bar_t == 0) return false;
   datetime bar_end = bar_t + (datetime)PeriodSeconds(InpZ_Timeframe);
   for(int i = 0; i < ArraySize(g_news_times); i++)
      if(g_news_times[i] >= bar_t && g_news_times[i] < bar_end) { name = g_news_names[i]; return true; }
   return false;
}

bool IsNewsBarT(datetime bar_t) { string nn; return IsNewsBar(bar_t, nn); }

string NextNewsText(datetime now) {
   if(!InpUseNewsTrend) return "";
   if(!NewsEnabled())   return "📰 ปฏิทินข่าวใช้ไม่ได้ใน Tester";
   string name;
   if(IsNewsBar(CurrentZBarTime(), name)) return "📰 แท่งข่าว (ตามน้ำ): " + name;
   datetime best = 0;
   string   best_name = "";
   for(int i = 0; i < ArraySize(g_news_times); i++)
      if(g_news_times[i] > now && (best == 0 || g_news_times[i] < best)) { best = g_news_times[i]; best_name = g_news_names[i]; }
   if(best == 0) return "📰 ไม่มีข่าว High ใน 24 ชม.";
   return StringFormat("📰 ข่าวถัดไป %s (อีก %s)", best_name, FormatDuration((long)(best - now)));
}

//====================================================================
// 🎯 SIGNAL: เฝ้าค่าสุดขั้ว No new high/low (ใช้ร่วมกันทั้ง EA จริงและ Tick Replay)
//====================================================================
bool HitZ(int dir, double zr, double zs) {
   return (dir == -1) ? LogicHit(zr >= InpSellZ, zs >= InpSellZ) : LogicHit(zr <= -InpBuyZ, zs <= -InpBuyZ);
}
bool SellHit() { return HitZ(-1, g_z_reg, g_z_sma); }
bool BuyHit()  { return HitZ( 1, g_z_reg, g_z_sma); }

void WatchReset(WatchState &w) {
   w.active   = false;
   w.ext_r    = 0.0;
   w.ext_s    = 0.0;
   w.last_new = 0;
   w.started  = 0;
}

// อัปเดตการเฝ้า: เริ่มเมื่อ Z ถึงเกณฑ์, รีเซ็ตเวลาเมื่อ Z ตัวใดทำค่าสุดขั้วใหม่ (Z หลุดเกณฑ์ระหว่างเฝ้าก็ไม่ยกเลิก)
void WatchUpdate(WatchState &w, int dir, double zr, double zs, long now_msc) {
   if(!w.active) {
      if(HitZ(dir, zr, zs)) {
         w.active   = true;
         w.ext_r    = zr;
         w.ext_s    = zs;
         w.last_new = now_msc;
         w.started  = now_msc;
      }
      return;
   }
   bool nr, ns;
   if(dir == -1) { nr = (zr > w.ext_r + InpNoNewExtEps); ns = (zs > w.ext_s + InpNoNewExtEps); }
   else          { nr = (zr < w.ext_r - InpNoNewExtEps); ns = (zs < w.ext_s - InpNoNewExtEps); }
   if(nr) w.ext_r = zr;
   if(ns) w.ext_s = zs;
   if(nr || ns) w.last_new = now_msc;
}

// ขึ้นแท่งใหม่: Z กระโดดเพราะค่าเฉลี่ย/ตัวหารเปลี่ยน → ตั้งค่าอ้างอิงใหม่โดยไม่นับเป็นค่าสุดขั้วใหม่
void WatchRebase(WatchState &w, double zr, double zs) {
   if(!w.active) return;
   w.ext_r = zr;
   w.ext_s = zs;
}

long WatchDeadline(const WatchState &w) { return w.last_new + (long)InpNoNewExt_Sec * 1000; }
bool WatchReady(const WatchState &w, long now_msc) { return w.active && now_msc >= WatchDeadline(w); }

// อยู่ในช่วงห้ามเปิดไม้ต้นแท่งไหม (เวลาแท่งของ TF ของ Z ตรงกับเวลาเซิร์ฟเวอร์หารลงตัว)
bool InBarStartDelay(datetime t) {
   long per = PeriodSeconds(InpZ_Timeframe);
   if(per <= 0) return false;
   return ((long)t % per) < (long)InpBarStartDelay_Sec;
}

// ตามน้ำในแท่งข่าว: Z บวกแรง → BUY / Z ลบแรง → SELL (0 = ยังไม่ถึง)
int NewsTrendDir(double zr, double zs) {
   if(LogicHit(zr >= InpNewsTrendZ,  zs >= InpNewsTrendZ))  return 1;
   if(LogicHit(zr <= -InpNewsTrendZ, zs <= -InpNewsTrendZ)) return -1;
   return 0;
}

double LotForStage(int stage) {
   if(stage <= 0) return NormalizeLot(InpLot);
   return NormalizeLot(InpLot + (stage - 1) * InpChainLotStep);
}

string StageTag(int stage) { return (stage <= 0) ? "NEWS" : ("C" + IntegerToString(stage)); }

// ตัวกรองตอนยิง (ใช้ร่วมกัน) — เหลือแค่เวลาตลาด + เพดานสเปรด
string EntryBlockReason(int ts, double bid, double ask) {
   if(ts != TS_OPEN) return "เวลาตลาด";
   double sp = PriceToPts(ask - bid);
   if(sp > InpMaxSpread_Pts) return StringFormat("สเปรด %.0f > %.0f จุด", sp, InpMaxSpread_Pts);
   return "";
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
// เปิด Market: stage 1-4 = ไม้ลูกโซ่ (มี TP/SL), 0 = ไม้ข่าว (ไม่มี TP)
bool OpenMarket(int dir, int stage, double bid, double ask, ulong &ticket) {
   double lot   = LotForStage(stage);
   double price = (dir == -1) ? bid : ask;
   double sl_d  = PtsToPrice(stage > 0 ? InpSL_Pts : InpNewsSL_Pts);
   double tp_d  = PtsToPrice(InpTP_Pts);
   double sl    = (sl_d > 0.0) ? ND(dir == -1 ? price + sl_d : price - sl_d) : 0.0;
   double tp    = (stage > 0)  ? ND(dir == -1 ? price - tp_d : price + tp_d) : 0.0;
   string cmt   = StringFormat("%s %s R%+.1f S%+.1f", InpOrderComment, StageTag(stage), g_z_reg, g_z_sma);
   bool   ok    = (dir == -1) ? trade.Sell(lot, _Symbol, bid, sl, tp, cmt)
                              : trade.Buy (lot, _Symbol, ask, sl, tp, cmt);
   uint rc = trade.ResultRetcode();
   if(ok && (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_PLACED || rc == TRADE_RETCODE_DONE_PARTIAL)) {
      ticket = trade.ResultOrder();
      PrintFormat("✅ เปิด %s %s %.2f lot @ %s | Z_reg %+.2f / Z_SMA %+.2f", StageTag(stage), (dir == -1 ? "SELL" : "BUY"),
                  lot, DoubleToString(trade.ResultPrice(), _Digits), g_z_reg, g_z_sma);
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

void DeleteOurPendings() {
   for(int i = OrdersTotal() - 1; i >= 0; i--) {
      ulong t = OrderGetTicket(i);
      if(t == 0) continue;
      if(OrderGetInteger(ORDER_MAGIC) != InpMagic || OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      trade.OrderDelete(t);
   }
}

//--------------------------------------------------------------------
// 🔗 ไม้ลูกโซ่ (EA จริง)
//--------------------------------------------------------------------
void ChainReset() {
   g_ch.active = false; g_ch.dir = 0; g_ch.stage = 0; g_ch.pos = 0;
   g_ch.pend = 0; g_ch.pend_stage = 0; g_ch.pend_price = 0.0; g_ch.pend_time = 0;
   g_ch.next_done = false;
}

void ChainEnd(string why) {
   if(g_ch.pend != 0) trade.OrderDelete(g_ch.pend);
   if(g_ch.active) PrintFormat("🔗 จบชุดลูกโซ่: %s", why);
   ChainReset();
}

void ChainCancelPending(string why) {
   if(g_ch.pend == 0) return;
   if(trade.OrderDelete(g_ch.pend)) PrintFormat("🔗 ยกเลิก Limit %s: %s", StageTag(g_ch.pend_stage), why);
   g_ch.pend = 0;
   g_ch.next_done = true;
}

// วาง Limit ไม้ถัดไป เลย SL ของไม้ปัจจุบันไป gap จุด
void ChainPlaceNext(double cur_sl) {
   if(!InpChainEnable || g_ch.stage >= 3 || cur_sl <= 0.0 || g_ch.next_done) return;
   if(IsNewsBarT(CurrentZBarTime())) { g_ch.next_done = true; return; }
   int    next  = g_ch.stage + 1;
   double gap   = PtsToPrice(next == 2 ? InpChainGap2_Pts : InpChainGap3_Pts);
   int    d     = g_ch.dir;
   double price = ND(d == -1 ? cur_sl + gap : cur_sl - gap);
   double sl    = ND(d == -1 ? price + PtsToPrice(InpSL_Pts) : price - PtsToPrice(InpSL_Pts));
   double tp    = ND(d == -1 ? price - PtsToPrice(InpTP_Pts) : price + PtsToPrice(InpTP_Pts));
   double lot   = LotForStage(next);
   string cmt   = StringFormat("%s %s", InpOrderComment, StageTag(next));
   bool   ok    = (d == -1) ? trade.SellLimit(lot, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt)
                            : trade.BuyLimit (lot, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt);
   if(ok && trade.ResultOrder() > 0) {
      g_ch.pend = trade.ResultOrder(); g_ch.pend_stage = next; g_ch.pend_price = price; g_ch.pend_time = ServerNow();
      g_ch.next_done = true;
      PrintFormat("🔗 วาง Limit %s %s %.2f lot @ %s", StageTag(next), (d == -1 ? "SELL" : "BUY"), lot, DoubleToString(price, _Digits));
   } else {
      PrintFormat("❌ วาง Limit %s ไม่สำเร็จ: %u %s", StageTag(next), trade.ResultRetcode(), trade.ResultRetcodeDescription());
   }
}

void ChainStart(int dir, ulong ticket) {
   ChainReset();
   g_ch.active = true; g_ch.dir = dir; g_ch.stage = 1; g_ch.pos = ticket;
   if(PositionSelectByTicket(ticket)) ChainPlaceNext(PositionGetDouble(POSITION_SL));
}

// ข้อมูลการปิดไม้จาก history: เหตุผล + กำไรสุทธิ (false = history ยังไม่มา)
bool LastCloseInfo(ulong pos_id, long &reason, double &profit) {
   if(!HistorySelectByPosition(pos_id)) return false;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--) {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0 || HistoryDealGetInteger(d, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
      reason = HistoryDealGetInteger(d, DEAL_REASON);
      profit = HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_SWAP) + HistoryDealGetDouble(d, DEAL_COMMISSION);
      return true;
   }
   return false;
}

// เรียกทุก 1 วินาที และหลังมีธุรกรรม
void ChainStep(datetime now) {
   if(!g_ch.active) return;

   // 1. ไม้ปัจจุบันปิดแล้ว?
   if(g_ch.pos != 0 && !PositionSelectByTicket(g_ch.pos)) {
      long reason = 0; double profit = 0.0;
      if(!LastCloseInfo(g_ch.pos, reason, profit)) return;   // รอ history
      g_ch.pos = 0;
      bool sl_loss = (reason == DEAL_REASON_SL && profit < 0.0);
      if(!sl_loss) { ChainEnd(StringFormat("%s จบแบบไม่ใช่ SL", StageTag(g_ch.stage))); return; }
      if(g_ch.stage == 3 && InpChainEnable && InpChainTrendLast) {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         ulong t = 0;
         if(GetTimeState(now) == TS_OPEN && OpenMarket(-g_ch.dir, 4, bid, ask, t)) {
            g_ch.stage = 4; g_ch.pos = t;
            g_last_status = "C3 ชน SL → เปิด C4 ตามน้ำ";
         } else ChainEnd("เปิด C4 ไม่สำเร็จ");
         return;
      }
      if(g_ch.stage >= 3 || g_ch.pend == 0) { ChainEnd(StringFormat("%s ชน SL", StageTag(g_ch.stage))); return; }
   }

   // 2. Limit ที่รออยู่
   if(g_ch.pend != 0) {
      if(OrderSelect(g_ch.pend)) {
         string why = "";
         if(now - g_ch.pend_time >= (datetime)(InpChainLimitLife_Min * 60)) why = "ครบอายุ";
         else if(g_ch.pos != 0 && IsActivated(g_ch.pos))                    why = "ไม้ก่อนหน้าเริ่มไล่จี้";
         else if(IsNewsBarT(CurrentZBarTime()))                             why = "เข้าแท่งข่าว";
         if(why != "") ChainCancelPending(why);
      }
      else if(PositionSelectByTicket(g_ch.pend)) {   // Limit fill แล้ว
         g_ch.stage = g_ch.pend_stage;
         g_ch.pos   = g_ch.pend;
         g_ch.pend  = 0;
         g_ch.next_done = false;
         g_last_status = StringFormat("Limit %s ถูก fill", StageTag(g_ch.stage));
         ChainPlaceNext(PositionGetDouble(POSITION_SL));
      }
      else g_ch.pend = 0;   // ถูกลบ/หมดอายุจากฝั่งโบรก
   }

   // 3. วาง Limit ไม้ถัดไปไม่สำเร็จตอนเปิดไม้ → ลองใหม่ (ถ้าไม้ยังไม่เริ่มไล่จี้)
   if(g_ch.pos != 0 && g_ch.pend == 0 && !g_ch.next_done && g_ch.stage < 3 &&
      PositionSelectByTicket(g_ch.pos) && !IsActivated(g_ch.pos))
      ChainPlaceNext(PositionGetDouble(POSITION_SL));

   if(g_ch.pos == 0 && g_ch.pend == 0) ChainEnd("ไม่มีไม้หรือ Limit เหลือ");
}

// ครบเวลาเฝ้าแล้ว → ตัวกรอง → C1 (ติดตัวกรอง = ทิ้งสัญญาณ)
void LiveFire(int dir, int ts, double bid, double ask) {
   WatchState w;
   if(dir == -1) w = g_wsell; else w = g_wbuy;
   string side = (dir == -1) ? "SELL" : "BUY";
   datetime now = ServerNow();

   string why = EntryBlockReason(ts, bid, ask);
   if(why == "" && (!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED)))
      why = "ปิด Algo Trading อยู่";
   if(why != "") {
      g_last_status = StringFormat("%s ครบ %d วิแล้ว แต่ติด: %s → ทิ้งสัญญาณ", side, InpNoNewExt_Sec, why);
      if(dir == -1) WatchReset(g_wsell); else WatchReset(g_wbuy);
      return;
   }
   if(now < g_next_try) return;

   ulong ticket = 0;
   if(OpenMarket(dir, 1, bid, ask, ticket)) {
      g_last_status = StringFormat("เปิด C1 %s | สุดขั้ว R %+.2f / S %+.2f → ตอนยิง R %+.2f / S %+.2f",
                                   side, w.ext_r, w.ext_s, g_z_reg, g_z_sma);
      WatchReset(g_wsell);
      WatchReset(g_wbuy);
      ChainStart(dir, ticket);
   } else {
      g_next_try    = now + 1;   // กันยิงคำสั่งรัว ๆ เมื่อโบรกปฏิเสธ (ยังเฝ้าต่อ)
      g_last_status = side + " ส่งคำสั่งไม่สำเร็จ: " + trade.ResultRetcodeDescription();
   }
}

// แท่งข่าว: ตามน้ำ 1 ไม้ต่อแท่ง
void LiveNewsStep(int ts, double bid, double ask) {
   if(g_news_traded_bar == g_zbar_time) return;
   int dir = NewsTrendDir(g_z_reg, g_z_sma);
   if(dir == 0) return;
   string why = EntryBlockReason(ts, bid, ask);
   if(why != "") { g_last_status = "แท่งข่าว: ตามน้ำผ่าน Z แต่ติด " + why; return; }
   datetime now = ServerNow();
   if(now < g_next_try) return;
   ulong ticket = 0;
   if(OpenMarket(dir, 0, bid, ask, ticket)) {
      g_news_traded_bar = g_zbar_time;
      g_last_status = StringFormat("แท่งข่าว: เปิดตามน้ำ %s ที่ R %+.2f / S %+.2f", (dir == -1 ? "SELL" : "BUY"), g_z_reg, g_z_sma);
   } else g_next_try = now + 1;
}

// เรียกทุก Tick และทุก 1 วินาที
void LiveSignalStep(long now_msc, int ts, double bid, double ask, bool update_watch) {
   if(!g_z_valid) return;
   datetime now_t    = (datetime)(now_msc / 1000);
   bool     busy     = g_ch.active || OurPositionsTotal() > 0;
   bool     early    = InBarStartDelay(now_t);
   bool     news_bar = IsNewsBarT(g_zbar_time);

   if(busy || early || news_bar) {
      WatchReset(g_wsell);
      WatchReset(g_wbuy);
      g_bar_changed = false;
      if(news_bar && !busy && !early) LiveNewsStep(ts, bid, ask);
      return;
   }
   if(g_bar_changed) {
      WatchRebase(g_wsell, g_z_reg, g_z_sma);
      WatchRebase(g_wbuy,  g_z_reg, g_z_sma);
      g_bar_changed = false;
   }
   if(update_watch) {
      WatchUpdate(g_wsell, -1, g_z_reg, g_z_sma, now_msc);
      WatchUpdate(g_wbuy,   1, g_z_reg, g_z_sma, now_msc);
   }
   if(WatchReady(g_wsell, now_msc))     LiveFire(-1, ts, bid, ask);
   else if(WatchReady(g_wbuy, now_msc)) LiveFire( 1, ts, bid, ask);
}

void CloseAllPositions() {
   DeleteOurPendings();
   if(g_ch.active) ChainEnd("ใกล้ตลาดปิดสัปดาห์");
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
      bool     news   = (StringFind(PositionGetString(POSITION_COMMENT), "NEWS") >= 0 || tp <= 0.0);   // ไม้ข่าว: ไม่ตัด 60 วิ

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
         else if(!news && InpQuickWindow_Sec > 0 && now - opened >= InpQuickWindow_Sec) {
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
//   (เฝ้า 3 วิ / นาทีแรกของแท่ง / ลูกโซ่ C1-C4 + Limit / แท่งข่าวตามน้ำ / TP / SL / โล่ / ตัด 60 วิ / ปิดสุดสัปดาห์)
//====================================================================
#define RX_OPEN   0
#define RX_TP     1
#define RX_SL     2
#define RX_CUT    3
#define RX_TRAIL  4
#define RX_WEEK   5

struct RTrade {
   long     msc_in;
   int      dir;
   int      stage;         // 0 = ข่าว, 1..4 = ลูกโซ่
   double   lot;
   double   p_in, sl, tp;
   double   zr, zs, ext_r, ext_s;
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

RTrade     g_rt[];
RBlocked   g_rb[];
int        g_rt_open      = -1;
int        g_rb_drawn     = 0;

// ลูกโซ่ / Limit / ข่าว ใน Replay
bool       g_rpc_active   = false;
int        g_rpc_dir      = 0;
int        g_rpc_stage    = 0;
bool       g_rpp_active   = false;
int        g_rpp_stage    = 0;
double     g_rpp_price    = 0.0;
long       g_rpp_msc      = 0;
datetime   g_rp_news_bar  = 0;

MqlRates   g_rr[];
int        g_rp_b         = -1;
datetime   g_rp_bar_t     = 0;
ZCache     g_rp_zc;
bool       g_rp_bar_chg   = false;
WatchState g_rp_ws;
WatchState g_rp_wb;
double     g_rp_bid = 0.0, g_rp_ask = 0.0, g_rp_zr = 0.0, g_rp_zs = 0.0;
long       g_rp_msc       = 0;
bool       g_rp_have      = false;
bool       g_rp_init      = false;
bool       g_rp_caught    = false;
long       g_rp_cursor    = 0;
int        g_rp_retry     = 0;
long       g_rp_ticks     = 0;
string     g_rp_status    = "ยังไม่เริ่ม";
double     g_contract     = 100.0;

void ReplayReset() {
   ArrayResize(g_rt, 0);
   ArrayResize(g_rb, 0);
   ArrayResize(g_rr, 0);
   g_rt_open = -1; g_rb_drawn = 0;
   g_rpc_active = false; g_rpc_dir = 0; g_rpc_stage = 0;
   g_rpp_active = false; g_rpp_stage = 0; g_rpp_price = 0.0; g_rpp_msc = 0;
   g_rp_news_bar = 0;
   g_rp_b = -1; g_rp_bar_t = 0; g_rp_zc.ok = false; g_rp_bar_chg = false;
   WatchReset(g_rp_ws); WatchReset(g_rp_wb);
   g_rp_bid = 0.0; g_rp_ask = 0.0; g_rp_zr = 0.0; g_rp_zs = 0.0;
   g_rp_msc = 0; g_rp_have = false; g_rp_init = false; g_rp_caught = false;
   g_rp_cursor = 0; g_rp_retry = 0; g_rp_ticks = 0;
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

void ReplayChainEnd() {
   g_rpc_active = false; g_rpc_dir = 0; g_rpc_stage = 0;
   g_rpp_active = false;
}

// วาง Limit ไม้ถัดไปเลย SL ของไม้ปัจจุบัน
void ReplayPlaceNext(int i, long msc) {
   if(!InpChainEnable || g_rt[i].stage < 1 || g_rt[i].stage >= 3) return;
   int    next = g_rt[i].stage + 1;
   double gap  = PtsToPrice(next == 2 ? InpChainGap2_Pts : InpChainGap3_Pts);
   g_rpp_active = true;
   g_rpp_stage  = next;
   g_rpp_price  = (g_rt[i].dir == -1) ? g_rt[i].sl + gap : g_rt[i].sl - gap;
   g_rpp_msc    = msc;
}

int ReplayOpen(int dir, int stage, long msc, double price) {
   int i = ArraySize(g_rt);
   ArrayResize(g_rt, i + 1);
   double sl_d = PtsToPrice(stage > 0 ? InpSL_Pts : InpNewsSL_Pts);
   double tp_d = PtsToPrice(InpTP_Pts);
   g_rt[i].msc_in   = msc;
   g_rt[i].dir      = dir;
   g_rt[i].stage    = stage;
   g_rt[i].lot      = LotForStage(stage);
   g_rt[i].p_in     = price;
   g_rt[i].sl       = (sl_d > 0.0) ? ((dir == -1) ? price + sl_d : price - sl_d) : 0.0;
   g_rt[i].tp       = (stage > 0)  ? ((dir == -1) ? price - tp_d : price + tp_d) : 0.0;
   g_rt[i].zr       = g_rp_zr;
   g_rt[i].zs       = g_rp_zs;
   g_rt[i].ext_r    = 0.0;
   g_rt[i].ext_s    = 0.0;
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

// ปิดไม้จำลอง + ต่อลูกโซ่ (bid/ask = ราคาตอนปิด ใช้เปิด C4)
void ReplayClose(long msc_out, double price, int reason, double bid, double ask) {
   int i = g_rt_open;
   if(i < 0) return;
   g_rt[i].msc_out = msc_out;
   g_rt[i].p_out   = price;
   g_rt[i].reason  = reason;
   double diff     = (g_rt[i].dir == -1) ? (g_rt[i].p_in - price) : (price - g_rt[i].p_in);
   g_rt[i].pnl     = PriceToPts(diff);
   g_rt[i].usd     = diff * g_rt[i].lot * g_contract;
   g_rt_open = -1;

   int stage = g_rt[i].stage;
   if(stage <= 0 || !g_rpc_active) return;           // ไม้ข่าวไม่เกี่ยวกับลูกโซ่
   if(reason == RX_WEEK)  { ReplayChainEnd(); return; }
   if(reason != RX_SL)    { ReplayChainEnd(); return; }   // จบแบบไม่ใช่ SL → จบชุด
   if(stage == 3 && InpChainEnable && InpChainTrendLast) {
      int d4 = -g_rt[i].dir;
      if(GetTimeStateAt((datetime)(msc_out / 1000)) == TS_OPEN) {
         int k = ReplayOpen(d4, 4, msc_out, (d4 == -1) ? bid : ask);
         g_rt[k].zr = g_rp_zr; g_rt[k].zs = g_rp_zs;
         g_rpc_stage = 4;
      } else ReplayChainEnd();
      return;
   }
   if(stage >= 3 || !g_rpp_active) ReplayChainEnd();
}

// ครบเวลาเฝ้า → ตัวกรอง → C1 (ราคา/Z ของ tick ก่อนหน้า)
void ReplayFire(int dir, long fire_msc) {
   datetime t = (datetime)(fire_msc / 1000);
   string why = InBarStartDelay(t) ? "นาทีแรกของแท่ง" : EntryBlockReason(GetTimeStateAt(t), g_rp_bid, g_rp_ask);
   if(why != "") {
      int k = ArraySize(g_rb);
      ArrayResize(g_rb, k + 1);
      g_rb[k].msc = fire_msc; g_rb[k].dir = dir; g_rb[k].why = why;
      g_rb[k].price = (dir == -1) ? g_rp_bid : g_rp_ask;
      if(dir == -1) WatchReset(g_rp_ws); else WatchReset(g_rp_wb);
      return;
   }
   double er = (dir == -1) ? g_rp_ws.ext_r : g_rp_wb.ext_r;
   double es = (dir == -1) ? g_rp_ws.ext_s : g_rp_wb.ext_s;
   int i = ReplayOpen(dir, 1, fire_msc, (dir == -1) ? g_rp_bid : g_rp_ask);
   g_rt[i].ext_r = er; g_rt[i].ext_s = es;
   g_rpc_active = true; g_rpc_dir = dir; g_rpc_stage = 1;
   ReplayPlaceNext(i, fire_msc);
}

// เหตุการณ์ตามเวลาระหว่าง tick ก่อนหน้า → tick นี้ (ราคายังเป็นของ tick ก่อนหน้า)
void ReplayTimeEvents(long msc) {
   if(!g_rp_have) return;
   if(g_rpp_active && msc - g_rpp_msc >= (long)InpChainLimitLife_Min * 60000) {
      g_rpp_active = false;
      if(g_rt_open < 0) ReplayChainEnd();
   }
   if(g_rt_open >= 0) {
      int  i   = g_rt_open;
      long wk  = (g_rt[i].force_close > 0) ? (long)g_rt[i].force_close * 1000 : LONG_MAX;
      long cut = (g_rt[i].stage > 0 && InpQuickWindow_Sec > 0 && !g_rt[i].activated)
                 ? g_rt[i].msc_in + (long)InpQuickWindow_Sec * 1000 : LONG_MAX;
      double px = (g_rt[i].dir == -1) ? g_rp_ask : g_rp_bid;
      if(wk <= cut && wk <= msc)       ReplayClose(wk,  px, RX_WEEK, g_rp_bid, g_rp_ask);
      else if(cut < wk && cut <= msc)  ReplayClose(cut, px, RX_CUT,  g_rp_bid, g_rp_ask);
      return;
   }
   if(g_rpc_active) return;
   if(WatchReady(g_rp_ws, msc))      ReplayFire(-1, WatchDeadline(g_rp_ws));
   else if(WatchReady(g_rp_wb, msc)) ReplayFire( 1, WatchDeadline(g_rp_wb));
}

// ไม้ที่ถืออยู่: SL / TP / โล่ ด้วยราคา tick ปัจจุบัน
void ReplayManageTick(long msc, double bid, double ask) {
   int i = g_rt_open;
   if(i < 0) return;
   int d = g_rt[i].dir;
   if(d == -1) {
      if(g_rt[i].sl > 0.0 && ask >= g_rt[i].sl) { ReplayClose(msc, ask, g_rt[i].activated ? RX_TRAIL : RX_SL, bid, ask); return; }
      if(g_rt[i].tp > 0.0 && ask <= g_rt[i].tp) { ReplayClose(msc, g_rt[i].tp, RX_TP, bid, ask); return; }
   } else {
      if(g_rt[i].sl > 0.0 && bid <= g_rt[i].sl) { ReplayClose(msc, bid, g_rt[i].activated ? RX_TRAIL : RX_SL, bid, ask); return; }
      if(g_rt[i].tp > 0.0 && bid >= g_rt[i].tp) { ReplayClose(msc, g_rt[i].tp, RX_TP, bid, ask); return; }
   }
   double prof = (d == -1) ? (g_rt[i].p_in - ask) : (bid - g_rt[i].p_in);
   long   sec  = msc / 1000;
   bool   do_trail = false;
   if(!g_rt[i].activated) {
      if(prof >= PtsToPrice(InpTrailStart_Pts)) {
         g_rt[i].activated = true;
         do_trail = true;
         if(g_rpp_active && g_rt[i].stage > 0) g_rpp_active = false;   // ไม้ก่อนหน้าเริ่มไล่จี้ → ยกเลิก Limit
      }
   }
   else if(sec - g_rt[i].last_trail_sec >= InpTrailInterval_Sec) do_trail = true;
   if(do_trail) {
      double dist = PtsToPrice(InpTrailDist_Pts);
      if(d == -1) { double nsl = ask + dist; if(g_rt[i].sl <= 0.0 || nsl < g_rt[i].sl) g_rt[i].sl = nsl; }
      else        { double nsl = bid - dist; if(nsl > g_rt[i].sl) g_rt[i].sl = nsl; }
      g_rt[i].last_trail_sec = sec;
   }
}

// Limit ลูกโซ่ถูก fill?
void ReplayPendingTick(long msc, double bid, double ask) {
   if(!g_rpp_active || g_rt_open >= 0) return;
   bool fill = (g_rpc_dir == -1) ? (bid >= g_rpp_price) : (ask <= g_rpp_price);
   if(!fill) return;
   if(GetTimeStateAt((datetime)(msc / 1000)) == TS_CLOSING) { ReplayChainEnd(); return; }
   g_rpp_active = false;
   int i = ReplayOpen(g_rpc_dir, g_rpp_stage, msc, g_rpp_price);
   g_rpc_stage = g_rpp_stage;
   ReplayPlaceNext(i, msc);
}

void ReplayTick(const MqlTick &tk) {
   double bid = tk.bid, ask = tk.ask;
   if(bid <= 0.0 || ask <= 0.0) return;
   long     msc = (long)tk.time_msc;
   datetime t   = (datetime)(msc / 1000);

   ReplayTimeEvents(msc);                 // A) เหตุการณ์ตามเวลาด้วยราคาเดิม
   if(!ReplayBarFor(t)) return;           // B) แท่งของ tick นี้
   bool news_bar = IsNewsBarT(g_rp_bar_t);
   if(news_bar && g_rpp_active) {         // เข้าแท่งข่าว → ยกเลิก Limit
      g_rpp_active = false;
      if(g_rt_open < 0) ReplayChainEnd();
   }

   double zr = 0.0, zs = 0.0, fit, sig, mn, ssd;
   bool   fl;
   bool   zok = ZAtPrice(g_rp_zc, bid, zr, zs, fit, sig, fl, mn, ssd);
   if(zok) { g_rp_zr = zr; g_rp_zs = zs; }

   if(g_rt_open >= 0) ReplayManageTick(msc, bid, ask);   // C) ไม้ที่ถืออยู่
   ReplayPendingTick(msc, bid, ask);                     // D) Limit ลูกโซ่

   // E) สัญญาณใหม่: ไม่มีไม้/ชุดค้าง + เลยนาทีแรกของแท่ง
   bool idle  = (g_rt_open < 0 && !g_rpc_active);
   bool early = InBarStartDelay(t);
   if(!idle || early || news_bar || !zok) { WatchReset(g_rp_ws); WatchReset(g_rp_wb); }
   if(idle && !early && zok) {
      if(news_bar) {
         if(g_rp_news_bar != g_rp_bar_t) {
            int nd = NewsTrendDir(zr, zs);
            if(nd != 0 && EntryBlockReason(GetTimeStateAt(t), bid, ask) == "") {
               ReplayOpen(nd, 0, msc, (nd == -1) ? bid : ask);
               g_rp_news_bar = g_rp_bar_t;
            }
         }
      } else {
         if(g_rp_bar_chg) { WatchRebase(g_rp_ws, zr, zs); WatchRebase(g_rp_wb, zr, zs); }
         WatchUpdate(g_rp_ws, -1, zr, zs, msc);
         WatchUpdate(g_rp_wb,  1, zr, zs, msc);
      }
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
      case RX_CUT:   return "ตัด60วิ";
      case RX_TRAIL: return "โล่";
      case RX_WEEK:  return "ปิดสัปดาห์";
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
   if(g_rt[i].stage == 1)
      tipText += StringFormat(" | สุดขั้วระหว่างเฝ้า R %+.2f / S %+.2f", g_rt[i].ext_r, g_rt[i].ext_s);
   tipText += StringFormat("\nห่างปลายไส้ %.0f จุด", gap);
   if(!open)
      tipText += StringFormat("\nออก %s @ %s (%s) | %+.0f จุด | $%+.2f | ถือ %d วินาที",
                              ReplayReasonName(g_rt[i].reason), DoubleToString(g_rt[i].p_out, _Digits),
                              TimeToString((datetime)(g_rt[i].msc_out / 1000), TIME_DATE|TIME_SECONDS),
                              g_rt[i].pnl, g_rt[i].usd, (int)((g_rt[i].msc_out - g_rt[i].msc_in) / 1000));
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

void ReplayDraw() {
   for(int i = 0; i < ArraySize(g_rt); i++)
      if(!g_rt[i].drawn_final) DrawReplayTrade(i);
   if(InpShowReplayBlocked)
      for(; g_rb_drawn < ArraySize(g_rb); g_rb_drawn++) DrawReplayBlocked(g_rb_drawn);
}

string ReplayStatsText() {
   if(!InpShowReplay) return "";
   int    n = 0, w = 0, c_tp = 0, c_sl = 0, c_cut = 0, c_tr = 0, c_wk = 0;
   int    cnt[5];
   double usd_st[5];
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
      int st = MathMax(0, MathMin(4, g_rt[i].stage));
      cnt[st]++;
      usd_st[st] += g_rt[i].usd;
      switch(g_rt[i].reason) {
         case RX_TP: c_tp++; break;   case RX_SL: c_sl++; break;   case RX_CUT: c_cut++; break;
         case RX_TRAIL: c_tr++; break; case RX_WEEK: c_wk++; break;
      }
   }
   string s = StringFormat("🧪 Replay %d วัน: %s\n   %d ไม้ | ชนะ %.0f%% | กำไรสุทธิ $%+.2f | DD $%.2f | TP %d SL %d ตัด60วิ %d โล่ %d ปิดสัปดาห์ %d | ถูกทิ้ง %d",
                           InpReplayDays, g_rp_status, n, (n > 0 ? 100.0 * w / n : 0.0), usd, dd,
                           c_tp, c_sl, c_cut, c_tr, c_wk, ArraySize(g_rb));
   s += StringFormat("\n   ตามลำดับไม้: C1 %d ($%+.2f) | C2 %d ($%+.2f) | C3 %d ($%+.2f) | C4 %d ($%+.2f) | ข่าว %d ($%+.2f)%s",
                     cnt[1], usd_st[1], cnt[2], usd_st[2], cnt[3], usd_st[3], cnt[4], usd_st[4], cnt[0], usd_st[0],
                     (g_rt_open >= 0 ? " | มีไม้จำลองถืออยู่" : (g_rpp_active ? " | มี Limit จำลองรออยู่" : "")));
   return s;
}

// เรียกทุก 1 วินาที: ไล่เล่นซ้ำทีละช่วง (ครั้งแรกทีละ 12 ชม.) จนถึงปัจจุบัน แล้วต่อแบบสด
void ReplayStep() {
   if(!g_draw || !InpShowReplay) return;
   if(!g_rp_init) {
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
   if(g_rp_caught) ReplayTimeEvents(now_msc);   // เวลาผ่านไปโดยไม่มี tick (ตัด 60 วิ / ยิงหลัง 3 วิ / Limit หมดอายุ)

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

// สีป้าย Z ตามโซน: ถึงเกณฑ์ = แดงส้ม/ฟ้า, ใกล้เกณฑ์ (เลยระดับ re-arm) = ทอง, ปกติ = เงิน
color LiveZColor(double z) {
   if(z >= InpSellZ)                   return InpClrLiveSell;
   if(z <= -InpBuyZ)                   return InpClrLiveBuy;
   if(z >= InpSellZ - NEAR_ZONE ||
      z <= -InpBuyZ + NEAR_ZONE)       return InpClrLiveNear;
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

string WatchShortText(const WatchState &w, long now_msc) {
   double left = (double)(WatchDeadline(w) - now_msc) / 1000.0;
   if(left < 0.0) left = 0.0;
   return StringFormat("เฝ้า ยิงใน %.1f วิ", left);
}

string WatchText(const WatchState &w, bool is_sell, long now_msc) {
   if(g_ch.active || OurPositionsTotal() > 0) return "⏸️ มีไม้/ชุดลูกโซ่ทำงานอยู่";
   if(IsNewsBarT(g_zbar_time))                 return "📰 แท่งข่าว → ปิดสวนกลับ ใช้ตามน้ำแทน";
   if(InBarStartDelay((datetime)(now_msc / 1000))) return StringFormat("⏳ %d วิแรกของแท่ง (ยังไม่เฝ้า)", InpBarStartDelay_Sec);
   if(w.active) {
      double left = (double)(WatchDeadline(w) - now_msc) / 1000.0;
      if(left < 0.0) left = 0.0;
      return StringFormat("👀 เฝ้า | สุดขั้ว R %+.2f / S %+.2f | ไม่มีค่าใหม่มา %.1f วิ → ยิงในอีก %.1f วิ",
                          w.ext_r, w.ext_s, (double)(now_msc - w.last_new) / 1000.0, left);
   }
   return StringFormat("✅ รอ %s %s %+.2f", LogicName(), (is_sell ? "≥" : "≤"), (is_sell ? InpSellZ : -InpBuyZ));
}

string ChainText(datetime now) {
   if(!g_ch.active) return "ไม่มีชุดทำงาน";
   string s = StringFormat("%s ชุด %s | ไม้ปัจจุบัน %s", (g_ch.dir == -1 ? "🔻" : "🔺"), (g_ch.dir == -1 ? "SELL" : "BUY"),
                           (g_ch.pos != 0 ? StageTag(g_ch.stage) : "-"));
   if(g_ch.stage == 4) s += " (ตามน้ำ)";
   if(g_ch.pend != 0) {
      long left = (long)InpChainLimitLife_Min * 60 - (long)(now - g_ch.pend_time);
      s += StringFormat(" | Limit %s %.2f lot @ %s (หมดอายุอีก %s)", StageTag(g_ch.pend_stage), LotForStage(g_ch.pend_stage),
                        DoubleToString(g_ch.pend_price, _Digits), FormatDuration(left));
   }
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
   string news_str = NextNewsText(now);

   long   now_msc = MathMax(g_last_tick_msc, (long)now * 1000);
   string msg = StringFormat("=== 📊 7-Lines Counter EA v8.00 (เข้าไม้: %s | No new high/low %d วิ | ลูกโซ่ %s | ข่าวตามน้ำ %s) ===\n",
                             LogicName(), InpNoNewExt_Sec, (InpChainEnable ? "เปิด" : "ปิด"), (InpUseNewsTrend ? "เปิด" : "ปิด"));
   msg += StringFormat("Z (%s, %d) : %s\n", EnumToString(InpZ_Timeframe), InpZ_Period, z_str);
   msg += StringFormat("Z แท่งที่เพิ่งปิด : R %+.2f / S %+.2f%s\n", g_prev_close_zr, g_prev_close_zs, (news_str == "" ? "" : " | " + news_str));
   msg += StringFormat("SELL (≥ +%.2f) : %s\n", InpSellZ, WatchText(g_wsell, true,  now_msc));
   msg += StringFormat("BUY  (≤ −%.2f) : %s\n", InpBuyZ,  WatchText(g_wbuy,  false, now_msc));
   msg += StringFormat("ออเดอร์ : BUY %d / SELL %d | สเปรด %.0f / %.0f จุด\n",
                       buys, sells, PriceToPts(ask - bid), InpMaxSpread_Pts);
   msg += "ลูกโซ่ : " + ChainText(now) + "\n";
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
   if(InpSellZ <= 0.0 || InpBuyZ <= 0.0 || InpNoNewExt_Sec < 0 || InpNoNewExtEps < 0.0) {
      Print("❌ ค่า Z ไม่ถูกต้อง");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpLot <= 0.0) { Print("❌ Lot ไม่ถูกต้อง"); return(INIT_PARAMETERS_INCORRECT); }
   if(InpTP_Pts <= 0.0 || InpSL_Pts <= 0.0 || InpTrailDist_Pts <= 0.0 || InpTrailInterval_Sec < 1) {
      Print("❌ TP / SL / ระยะโล่ / รอบไล่จี้ ไม่ถูกต้อง");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpQuickWindow_Sec < 0) {
      Print("❌ เวลาตัดจบต้องไม่ติดลบ");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpSigmaFloorMult < 0.0 || InpBarStartDelay_Sec < 0 || InpChainGap2_Pts < 0.0 || InpChainGap3_Pts < 0.0 ||
      InpChainLotStep < 0.0 || InpChainLimitLife_Min < 1 || InpNewsTrendZ <= 0.0 || InpNewsSL_Pts < 0.0) {
      Print("❌ ค่าพื้นตัวหาร / เวลาต้นแท่ง / ลูกโซ่ / ข่าว ไม่ถูกต้อง");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpUseNewsTrend && MQLInfoInteger(MQL_TESTER))
      Print("ℹ️ ปฏิทินข่าวใช้ไม่ได้ใน Strategy Tester — โหมดตามน้ำแท่งข่าวจะไม่ทำงาน");
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
   g_news_traded_bar = 0;
   ChainReset();
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

   RefreshNews(ServerNow());
   DeleteOurPendings();   // Limit ค้างจากรอบก่อน (สถานะลูกโซ่ไม่ถูกเก็บข้ามการรีสตาร์ท)

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
   LiveSignalStep(g_last_tick_msc, ts, tk.bid, tk.ask, true);
}

void OnTimer() {
   datetime now = ServerNow();
   int ts = GetTimeState(now);
   RefreshNews(now);

   // 1. บังคับปิดก่อนตลาดปิดสัปดาห์ / จัดการไม้ (เปิดไล่จี้, ตัดจบตามเวลา, ขยับโล่)
   if(ts == TS_CLOSING)     CloseAllPositions();
   else if(ts != TS_CLOSED) ManagePositions(now);
   ChainStep(now);

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
   ChainStep(ServerNow());   // ไม้ในชุดปิด / Limit fill → ต่อลูกโซ่ทันที (เช่นเปิด C4)
}
//+------------------------------------------------------------------+
