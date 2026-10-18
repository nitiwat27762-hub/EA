//+------------------------------------------------------------------+
//|                                       Seven_Lines_Counter_EA.mq5 |
//|      Fast Mean-Reversion Z-Score EA for XAUUSD (Indicator v8.82)  |
//+------------------------------------------------------------------+
//
// 🆕 v9.00: C1 = Limit ที่ระดับ Z (คำนวณล่วงหน้า) + ระบบเงา C1-C4 + โหมดตามน้ำปกติ
//  • ภายในแท่งเดียวกัน Z ขึ้นกับราคาปัจจุบันตัวเดียว (แท่งปิดถูกแคช) → ราคาที่ Z ถึงเกณฑ์คงที่ทั้งแท่ง
//    หาด้วย bisection ครั้งเดียวตอนขึ้นแท่งใหม่ (ทั้งคู่: SELL = ระดับที่สูงกว่า / BUY = ระดับที่ต่ำกว่า)
//  • ว่าง + เลยนาทีแรก + ไม่ใช่แท่งข่าว + สเปรดผ่าน → วาง Sell Limit / Buy Limit C1 ที่ระดับ Z พร้อมกัน (OCO)
//    ราคาเลยระดับอยู่แล้ว → รอราคากลับเข้าฝั่งปกติก่อนค่อยวาง | ขึ้นแท่งใหม่ → ย้าย Limit ไประดับใหม่
//  • ระบบเงา: ยึดราคา C1 ที่ fill → กาง C2 / C3 / C4 (ระยะจาก C1) — C2, C3 ไม่มีออเดอร์จริง จำแค่ระดับลึกสุดที่ราคาแตะ
//    ไม้ชน SL → ราคาวกกลับมาแตะ C1 → สวนกลับที่ C1 ด้วย Lot ของระดับลึกสุด (R2 = Lot C2, R3 = Lot C3)
//    เข้าซ้ำได้อีกเฉพาะเมื่อราคาไปถึงระดับที่ลึกกว่าเดิม | แตะ C4 → ตามน้ำทันที (Lot C4)
//    ไม้ใดปิดแบบไม่ใช่ SL / C4 ปิด / รอเงาเกินอายุ → จบรอบ
//  • ตามน้ำปกติ (เปิด/ปิดได้): Z_reg > +2.4 และ Z_SMA อยู่ใน 0.0–1.0 → BUY | Z_reg < −2.4 และ Z_SMA อยู่ใน −1.0–0.0 → SELL
//  • ทีละรอบ: รอบสวน / ไม้ข่าว / ตามน้ำปกติ ใช้ล็อกเดียวกัน — ระหว่างมีรอบ ไม่มี Limit C1 และไม่รับสัญญาณใหม่
//  • ยกเลิก: จับเวลา No new high/low, Limit ลูกโซ่ C2/C3 จริง
//  • เส้นระดับ C1 รายแท่ง (ขั้นบันได) + บันไดเงาของแต่ละรอบใน Tick Replay
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
// 📋 ตรรกะการเข้าไม้ (v9.00) — ทำงานทีละรอบ
//  แท่งปกติ: ว่าง + เลยนาทีแรก ──► Limit C1 ที่ระดับ Z ──(fill)──► รอบเงา: R2 / R3 สวนที่ C1, แตะ C4 ตามน้ำ
//            |Z_reg| > 2.4 และ Z_SMA ทิศเดียวกันอยู่ใน 0-1 ──► ตามน้ำปกติ 1 ไม้
//  แท่งข่าว: เลยนาทีแรก + ว่าง ──(|Z| ≥ 2.0)──► ตามน้ำ 1 ไม้
//  • ตัวกรอง: เวลาตลาด + สเปรด
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
#property version     "9.00"
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
input ENUM_ENTRY_LOGIC InpEntryLogic       = ENTRY_BOTH; // เงื่อนไข Z ที่ใช้หาระดับ Limit C1
input double          InpSellZ             = 2.50;       // Limit C1 SELL ที่ราคาซึ่ง Z = +ค่านี้ (สวนขาขึ้น)
input double          InpBuyZ              = 3.00;       // Limit C1 BUY ที่ราคาซึ่ง Z = −ค่านี้ (สวนขาลง)
input double          InpSigmaFloorMult    = 0.50;       // ตัวหาร Z ต้องไม่น้อยกว่า ค่านี้ × StdDev ของการเปลี่ยนแปลงราคาต่อแท่ง

input group "=== 2. ออเดอร์ ==="
input double          InpLot               = 0.01;       // Lot เริ่มต้น (C1 / ตามน้ำปกติ / ข่าว)
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
input int             InpQuickWindow_Sec   = 60;         // ไม้ C1-C4 / R2-R3 / ตามน้ำปกติ ต้องเข้าระบบไล่จี้ภายในกี่วินาที ไม่งั้นตัดจบ (0 = ปิด)
input int             InpBarStartDelay_Sec = 60;         // วาง Limit / เปิดไม้ใหม่ได้หลังแท่ง (TF ของ Z) เปิดแล้วกี่วินาที

input group "=== 5. ระบบเงา C1-C4 (ช่วงปกติ) ==="
input bool            InpShadowEnable      = true;       // เปิดระบบเงา (ปิด = มีแค่ C1 แล้วจบรอบ)
input double          InpShadowC2_Pts      = 3500.0;     // ระดับ C2 ห่างจากราคา C1 (จุด)
input double          InpShadowC3_Pts      = 6500.0;     // ระดับ C3 ห่างจากราคา C1 (จุด)
input double          InpShadowC4_Pts      = 9000.0;     // ระดับ C4 ห่างจากราคา C1 (จุด)
input double          InpLotStep           = 0.01;       // Lot เพิ่มต่อระดับ (C2 = Lot+step, C3 = Lot+2·step, C4 = Lot+3·step)
input int             InpRoundLife_Min     = 30;         // อายุรอบเงา (นาที นับจากเหตุการณ์ล่าสุด) ไม่กลับ C1 / ไม่ถึง C4 → จบรอบ
input bool            InpShadowTrendC4     = true;       // ราคาแตะ C4 → เปิดตามน้ำทันที

input group "=== 6. ตามน้ำปกติ (แท่งที่ไม่ใช่ข่าว) ==="
input bool            InpTrendEnable       = true;       // เปิดโหมดตามน้ำปกติ
input double          InpTrendZR           = 2.4;        // |Z_reg| ต้องมากกว่าค่านี้
input double          InpTrendSmaMin       = 0.0;        // |Z_SMA| ต่ำสุด (ทิศเดียวกับ Z_reg)
input double          InpTrendSmaMax       = 1.0;        // |Z_SMA| สูงสุด (ทิศเดียวกับ Z_reg)

input group "=== 7. แท่งข่าว (ตามน้ำ) ==="
input bool            InpUseNewsTrend      = true;       // แท่งที่มีข่าว USD High: ปิดสวนกลับ → ตามน้ำ (ใช้ไม่ได้ใน Tester)
input string          InpNewsCurrency      = "USD";      // สกุลเงินของข่าว
input double          InpNewsTrendZ        = 2.0;        // ตามน้ำเมื่อ |Z| ≥ ค่านี้ (ตาม InpEntryLogic)
input double          InpNewsSL_Pts        = 2500.0;     // SL ไม้ข่าว (จุด, 0 = ไม่มี SL) — ไม่มี TP, ใช้ไล่จี้

input group "=== 8. ตัวกรองทั่วไป ==="
input double          InpMaxSpread_Pts     = 800.0;      // สเปรดสูงสุดที่ยอมให้วาง Limit / เข้าไม้ (จุด)
input int             InpNoTradeAfterOpen_Min = 60;      // ห้ามเข้าไม้หลังตลาดเปิดสัปดาห์ (นาที)
input int             InpCloseBeforeClose_Min = 30;      // ปิดทุกไม้ก่อนตลาดปิดสัปดาห์ (นาที)

input group "=== 9. การแสดงผล ==="
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
input bool            InpShowC1Levels      = true;       // เส้นระดับ Limit C1 (ราคาที่ Z ถึงเกณฑ์) รายแท่ง
input int             InpLevelBars         = 200;        // จำนวนแท่งย้อนหลัง (TF ของ Z) ที่วาดเส้นระดับ C1
input bool            InpShowLadder        = true;       // วาดบันไดเงา C1-C4 ของแต่ละรอบ
input bool            InpShowReplay        = true;       // Tick Replay: จำลองไม้ย้อนหลังจาก tick จริง + ผลแต่ละไม้
input int             InpReplayDays        = 10;         // Tick Replay: ย้อนหลังกี่วัน (1-60)
input bool            InpShowReplayBlocked = true;       // Tick Replay: มาร์กจุดที่ราคาแตะระดับ C1 แต่ไม่มี Limit รอ
input bool            InpShowNewsHistory   = true;       // แสดงช่วงข่าวบนกราฟ (ย้อนหลัง + 24 ชม.ข้างหน้า)
input bool            InpNewsIncludeMedium = false;      // แสดงข่าวระดับ Medium ด้วย (การงดเทรดยังใช้เฉพาะ High)

input group "=== 10. สี ==="
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
input color           InpClrC1Sell         = clrOrangeRed;      // เส้นระดับ Limit C1 SELL
input color           InpClrC1Buy          = clrDeepSkyBlue;    // เส้นระดับ Limit C1 BUY
input color           InpClrLadder         = clrKhaki;          // บันไดเงา C1-C4
input color           InpClrSimSell        = clrViolet;         // มาร์กจำลอง: SELL
input color           InpClrSimBuy         = clrPaleGreen;      // มาร์กจำลอง: BUY
input color           InpClrSimWin         = clrLimeGreen;      // มาร์กจำลอง: เส้นเข้า→ออก ไม้กำไร
input color           InpClrSimLoss        = clrTomato;         // มาร์กจำลอง: เส้นเข้า→ออก ไม้ขาดทุน
input color           InpClrSimBlocked     = clrDimGray;        // มาร์กจำลอง: ราคาแตะระดับ C1 แต่ไม่มี Limit รอ
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

// ระดับราคา Limit C1 ของแท่ง (ราคาที่ Z ถึงเกณฑ์ — คงที่ทั้งแท่ง)
struct BarLevels {
   bool   sell_ok, buy_ok;
   double sell_px, buy_px;
};

// รอบการทำงาน (ทีละรอบ) — ใช้ร่วมกันทั้ง EA จริงและ Tick Replay
#define RK_NONE     0
#define RK_COUNTER  1   // รอบสวนกลับ: C1 + ระบบเงา
#define RK_NEWS     2   // ไม้ตามน้ำแท่งข่าว
#define RK_TREND    3   // ไม้ตามน้ำปกติ
#define ST_NEWS     0   // ลำดับไม้: 0 = ข่าว, 1 = C1, 2 = R2, 3 = R3, 4 = C4, 5 = ตามน้ำปกติ
#define ST_TREND    5
#define SH_NONE     0   // การกระทำของระบบเงา
#define SH_REENTRY  1
#define SH_C4       2
#define SH_EXPIRE   3

struct RoundState {
   int    kind;
   int    dir;         // ทิศของรอบ (รอบสวน = ทิศสวนกลับ)
   double c1;          // ราคา C1 ที่ fill (จุดยึดบันได)
   int    deepest;     // ระดับลึกสุดที่ราคาแตะ (1-3)
   int    used;        // ระดับที่ใช้ Lot เข้าไปแล้ว (กันเข้าซ้ำวนที่ C1)
   bool   in_pos;      // มีไม้ของรอบถืออยู่
   int    stage;       // ไม้ล่าสุดของรอบ
   long   start_msc;
   long   evt_msc;     // เหตุการณ์ล่าสุด (นับอายุรอบเงา)
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

// --- รอบ / Limit C1 (EA จริง) ---
long       g_last_tick_msc  = 0;
datetime   g_next_try       = 0;
string     g_last_status    = "เริ่มทำงาน";
string     g_idle_note      = "";     // เหตุผลที่ยังไม่วาง Limit C1
ulong      g_activated[];             // ไม้ที่ระบบไล่จี้เริ่มทำงานแล้ว
BarLevels  g_lv;                      // ระดับ Limit C1 ของแท่งปัจจุบัน
RoundState g_rd;
ulong      g_rd_pos         = 0;      // ไม้ของรอบที่ถืออยู่
ulong      g_lim_s          = 0;      // Sell Limit C1
ulong      g_lim_b          = 0;      // Buy Limit C1
datetime   g_news_traded_bar = 0;     // แท่งข่าวที่เปิดไม้ตามน้ำไปแล้ว

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

// ราคาที่ Z (which 0 = Regression / 1 = SMA) ข้ามค่า target — ภายในแท่ง Z เพิ่มตามราคา
// upper = true → ราคาต่ำสุดที่ Z ≥ target (SELL), false → ราคาสูงสุดที่ Z < target (BUY)
bool SolveZPrice(const ZCache &zc, int which, double target, bool upper, double &px) {
   double zr, zs, fit, sig, mn, ssd;
   bool   fl;
   double p = zc.last_close;
   if(!ZAtPrice(zc, p, zr, zs, fit, sig, fl, mn, ssd)) return false;
   double z     = (which == 0) ? zr : zs;
   double step  = MathMax(ssd, PtsToPrice(100.0));
   double dirv  = (z < target) ? 1.0 : -1.0;
   double lo    = 0.0, hi = 0.0;
   bool   found = false;
   for(int k = 0; k < 40 && !found; k++) {   // ขยายช่วงจนคร่อม target
      double q = p + dirv * step;
      if(q <= 0.0 || !ZAtPrice(zc, q, zr, zs, fit, sig, fl, mn, ssd)) return false;
      double zq = (which == 0) ? zr : zs;
      if(dirv > 0.0 ? (zq >= target) : (zq < target)) { lo = MathMin(p, q); hi = MathMax(p, q); found = true; }
      else { p = q; step *= 1.6; }
   }
   if(!found) return false;   // Z ไปไม่ถึง (Z มีเพดานจากจำนวนแท่ง)
   for(int k = 0; k < 60 && hi - lo > _Point * 0.05; k++) {
      double m = 0.5 * (lo + hi);
      if(!ZAtPrice(zc, m, zr, zs, fit, sig, fl, mn, ssd)) return false;
      if(((which == 0) ? zr : zs) >= target) hi = m; else lo = m;
   }
   px = upper ? hi : lo;
   return true;
}

// ระดับ Limit C1 ของแท่ง: ทั้งคู่ → SELL ใช้ระดับที่สูงกว่า / BUY ใช้ระดับที่ต่ำกว่า (ต้องผ่านเกณฑ์ทั้งสองค่า)
void ComputeLevels(const ZCache &zc, BarLevels &lv) {
   lv.sell_ok = false; lv.buy_ok = false; lv.sell_px = 0.0; lv.buy_px = 0.0;
   if(!zc.ok) return;
   bool   use_r = (InpEntryLogic != ENTRY_SMA);
   bool   use_s = (InpEntryLogic != ENTRY_REGRESSION);
   double pr = 0.0, ps = 0.0;
   if((!use_r || SolveZPrice(zc, 0, InpSellZ, true, pr)) && (!use_s || SolveZPrice(zc, 1, InpSellZ, true, ps))) {
      lv.sell_px = (use_r && use_s) ? MathMax(pr, ps) : (use_r ? pr : ps);
      lv.sell_ok = true;
   }
   if((!use_r || SolveZPrice(zc, 0, -InpBuyZ, false, pr)) && (!use_s || SolveZPrice(zc, 1, -InpBuyZ, false, ps))) {
      lv.buy_px = (use_r && use_s) ? MathMin(pr, ps) : (use_r ? pr : ps);
      lv.buy_ok = true;
   }
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
   ComputeLevels(g_zc, g_lv);   // ระดับ Limit C1 ของแท่งใหม่ (คงที่ทั้งแท่ง)

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
// 🎯 SIGNAL & รอบ (ใช้ร่วมกันทั้ง EA จริงและ Tick Replay)
//====================================================================
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

// ตามน้ำปกติ: Z_reg แรง แต่ราคายังใกล้ SMA20 (Z_SMA ทิศเดียวกันอยู่ในช่วงที่กำหนด) → ตามทิศ Z_reg
int TrendNormalDir(double zr, double zs) {
   if(!InpTrendEnable) return 0;
   if(zr >  InpTrendZR && zs >=  InpTrendSmaMin && zs <=  InpTrendSmaMax) return 1;
   if(zr < -InpTrendZR && zs <= -InpTrendSmaMin && zs >= -InpTrendSmaMax) return -1;
   return 0;
}

// Lot: C1-C4 / R2-R3 ตามระดับ, ข่าว / ตามน้ำปกติ = Lot เริ่มต้น
double LotForStage(int stage) {
   if(stage <= ST_NEWS || stage >= ST_TREND) return NormalizeLot(InpLot);
   return NormalizeLot(InpLot + (stage - 1) * InpLotStep);
}

string StageTag(int stage) {
   switch(stage) {
      case ST_NEWS:  return "NEWS";
      case 1:        return "C1";
      case 2:        return "R2";
      case 3:        return "R3";
      case 4:        return "C4";
      case ST_TREND: return "TREND";
   }
   return "?";
}

// ตัวกรองตอนวาง Limit / เปิดไม้ (ใช้ร่วมกัน) — เวลาตลาด + เพดานสเปรด
string EntryBlockReason(int ts, double bid, double ask) {
   if(ts != TS_OPEN) return "เวลาตลาด";
   double sp = PriceToPts(ask - bid);
   if(sp > InpMaxSpread_Pts) return StringFormat("สเปรด %.0f > %.0f จุด", sp, InpMaxSpread_Pts);
   return "";
}

bool TradeAllowed() {
   return TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) && MQLInfoInteger(MQL_TRADE_ALLOWED);
}

//--- รอบ + ระบบเงา ---
void RoundReset(RoundState &r) {
   r.kind = RK_NONE; r.dir = 0; r.c1 = 0.0; r.deepest = 0; r.used = 0;
   r.in_pos = false; r.stage = 0; r.start_msc = 0; r.evt_msc = 0;
}

void RoundBegin(RoundState &r, int kind, int dir, int stage, double price, long msc) {
   RoundReset(r);
   r.kind = kind; r.dir = dir; r.c1 = price; r.deepest = 1; r.used = 1;
   r.in_pos = true; r.stage = stage; r.start_msc = msc; r.evt_msc = msc;
}

double LadderDist(int lv) {
   if(lv <= 1) return 0.0;
   return PtsToPrice(lv == 2 ? InpShadowC2_Pts : (lv == 3 ? InpShadowC3_Pts : InpShadowC4_Pts));
}

// ราคาระดับ lv ของรอบ (SELL: เหนือ C1 / BUY: ใต้ C1)
double LadderPrice(const RoundState &r, int lv) { return r.c1 - r.dir * LadderDist(lv); }

// ราคาที่ใช้วัดบันได: รอบ SELL ใช้ Bid / รอบ BUY ใช้ Ask (ฝั่งเดียวกับที่เปิดไม้สวน)
double RoundPx(const RoundState &r, double bid, double ask) { return (r.dir == -1) ? bid : ask; }
bool   PastLevel(const RoundState &r, double px, double level) { return (r.dir == -1) ? (px >= level) : (px <= level); }

// จำระดับลึกสุดที่ราคาแตะ (C2 / C3)
void RoundTrack(RoundState &r, double bid, double ask, long msc) {
   if(r.kind != RK_COUNTER || !InpShadowEnable) return;
   double px = RoundPx(r, bid, ask);
   for(int lv = 3; lv > r.deepest; lv--)
      if(PastLevel(r, px, LadderPrice(r, lv))) { r.deepest = lv; r.evt_msc = msc; break; }
}

bool RoundExpired(const RoundState &r, long msc) {
   return (r.kind == RK_COUNTER && !r.in_pos && msc - r.evt_msc >= (long)InpRoundLife_Min * 60000);
}

// รอเงา (ไม่มีไม้ถือ): แตะ C4 → ตามน้ำ / กลับถึง C1 และเคยไปลึกกว่าเดิม → สวนด้วย Lot ระดับลึกสุด
int RoundShadowAction(const RoundState &r, double bid, double ask, long msc) {
   if(r.kind != RK_COUNTER || r.in_pos || !InpShadowEnable) return SH_NONE;
   if(RoundExpired(r, msc)) return SH_EXPIRE;
   double px = RoundPx(r, bid, ask);
   if(InpShadowTrendC4 && PastLevel(r, px, LadderPrice(r, 4))) return SH_C4;
   if(r.deepest > r.used && ((r.dir == -1) ? (px <= r.c1) : (px >= r.c1))) return SH_REENTRY;
   return SH_NONE;
}

void RoundOpened(RoundState &r, int stage, long msc) {
   r.in_pos = true; r.stage = stage; r.evt_msc = msc;
   if(stage >= 1 && stage <= 3) r.used = stage;
}

// ไม้ของรอบปิด → true = รอบเดินต่อ (รอเงา), false = จบรอบ
bool RoundAfterClose(RoundState &r, bool sl_loss, long msc) {
   r.in_pos = false; r.evt_msc = msc;
   if(r.kind != RK_COUNTER || !InpShadowEnable) return false;
   return (sl_loss && r.stage >= 1 && r.stage <= 3);
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
// เปิด Market: stage 1-5 = C1 / R2 / R3 / C4 / ตามน้ำปกติ (มี TP/SL), 0 = ไม้ข่าว (ไม่มี TP)
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
// 🔁 รอบ + Limit C1 + ระบบเงา (EA จริง)
//--------------------------------------------------------------------
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

// ลบ Limit C1 — false = Limit ถูก fill ไปแล้ว (ปล่อยให้ LiveRoundSync รับเป็นรอบ)
bool DeleteLimit(ulong &tk) {
   if(tk == 0) return true;
   if(OrderSelect(tk)) {
      if(trade.OrderDelete(tk)) { tk = 0; return true; }
      return false;
   }
   if(PositionSelectByTicket(tk)) return false;
   tk = 0;
   return true;
}

bool LiveDeleteLimits() {
   bool a = DeleteLimit(g_lim_s);
   bool b = DeleteLimit(g_lim_b);
   return a && b;
}

// Limit C1 ถูก fill แล้ว? (ไม่อยู่ในรายการ Pending แต่มีโพซิชัน ticket เดียวกัน — เลือกโพซิชันไว้ให้)
bool LimitFilled(ulong &tk) {
   if(tk == 0 || OrderSelect(tk)) return false;
   if(PositionSelectByTicket(tk)) return true;
   tk = 0;   // ถูกลบ/ยกเลิกจากฝั่งโบรก
   return false;
}

// วาง / ย้าย Limit C1 ให้อยู่ที่ระดับ Z ของแท่งนี้ (ราคาเลยระดับอยู่ → รอกลับก่อนค่อยวาง)
void EnsureLimit(int dir, ulong &tk, bool ok, double level, double bid, double ask) {
   if(!ok) { DeleteLimit(tk); return; }
   double px    = ND(level);
   double stops = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   bool   side  = (dir == -1) ? (px - bid > stops) : (ask - px > stops);
   double sl    = ND(dir == -1 ? px + PtsToPrice(InpSL_Pts) : px - PtsToPrice(InpSL_Pts));
   double tp    = ND(dir == -1 ? px - PtsToPrice(InpTP_Pts) : px + PtsToPrice(InpTP_Pts));
   if(tk != 0) {
      if(!OrderSelect(tk)) return;                                                 // fill / หาย → LiveRoundSync จัดการ
      if(MathAbs(OrderGetDouble(ORDER_PRICE_OPEN) - px) < _Point * 0.5) return;    // อยู่ที่ระดับแล้ว
      if(!side) { DeleteLimit(tk); return; }
      if(!trade.OrderModify(tk, px, sl, tp, ORDER_TIME_GTC, 0)) DeleteLimit(tk);
      return;
   }
   if(!side) return;
   datetime now = ServerNow();
   if(now < g_next_try) return;
   double lot = LotForStage(1);
   string cmt = StringFormat("%s C1", InpOrderComment);
   bool   res = (dir == -1) ? trade.SellLimit(lot, px, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt)
                            : trade.BuyLimit (lot, px, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt);
   if(res && trade.ResultOrder() > 0) {
      tk = trade.ResultOrder();
      PrintFormat("📌 วาง Limit C1 %s %.2f lot @ %s", (dir == -1 ? "SELL" : "BUY"), lot, DoubleToString(px, _Digits));
   } else {
      g_next_try = now + 1;
      PrintFormat("❌ วาง Limit C1 %s ไม่สำเร็จ: %u %s", (dir == -1 ? "SELL" : "BUY"), trade.ResultRetcode(), trade.ResultRetcodeDescription());
   }
}

void LiveRoundBegin(int kind, int dir, int stage, double price, ulong ticket, long msc) {
   RoundBegin(g_rd, kind, dir, stage, price, msc);
   g_rd_pos = ticket;
}

void LiveRoundEnd(string why) {
   if(g_rd.kind == RK_COUNTER) DrawLiveLadder(ServerNow());
   PrintFormat("🔁 จบรอบ: %s", why);
   g_last_status = "จบรอบ: " + why;
   RoundReset(g_rd);
   g_rd_pos = 0;
}

// รับ Limit C1 ที่ fill เป็นรอบใหม่ + ตรวจไม้ของรอบที่ปิดแล้ว (ทุก tick / 1 วินาที / หลังมีธุรกรรม)
void LiveRoundSync(long msc) {
   if(g_rd.kind == RK_NONE) {
      int   dir = 0;
      ulong tk  = 0;
      if(LimitFilled(g_lim_s))      { dir = -1; tk = g_lim_s; g_lim_s = 0; }
      else if(LimitFilled(g_lim_b)) { dir =  1; tk = g_lim_b; g_lim_b = 0; }
      if(dir != 0) {
         double px = PositionGetDouble(POSITION_PRICE_OPEN);
         LiveDeleteLimits();   // OCO: ลบอีกฝั่ง
         LiveRoundBegin(RK_COUNTER, dir, 1, px, tk, msc);
         g_last_status = StringFormat("Limit C1 %s fill @ %s → เริ่มรอบ", (dir == -1 ? "SELL" : "BUY"), DoubleToString(px, _Digits));
         PrintFormat("✅ %s", g_last_status);
      }
   }
   if(g_rd.kind == RK_NONE || !g_rd.in_pos || g_rd_pos == 0 || PositionSelectByTicket(g_rd_pos)) return;

   long reason = 0; double profit = 0.0;
   if(!LastCloseInfo(g_rd_pos, reason, profit)) return;   // รอ history
   bool   sl_loss = (reason == DEAL_REASON_SL && profit < 0.0);
   string tag     = StageTag(g_rd.stage);
   g_rd_pos = 0;
   if(RoundAfterClose(g_rd, sl_loss, msc))
      g_last_status = StringFormat("%s ชน SL → เงา: รอราคากลับ C1 %s (ลึกสุด C%d)", tag, DoubleToString(g_rd.c1, _Digits), g_rd.deepest);
   else
      LiveRoundEnd(StringFormat("%s ปิด%s", tag, (sl_loss ? "ด้วย SL" : "แบบไม่ใช่ SL")));
}

// รอบสวนกลับ: จำระดับลึกสุด + เงา (สวนที่ C1 ด้วย Lot ระดับลึกสุด / แตะ C4 ตามน้ำ)
void LiveShadowStep(long msc, int ts, double bid, double ask) {
   if(g_rd.kind != RK_COUNTER) return;
   RoundTrack(g_rd, bid, ask, msc);
   int act = RoundShadowAction(g_rd, bid, ask, msc);
   if(act == SH_NONE) return;
   if(act == SH_EXPIRE) { LiveRoundEnd(StringFormat("รอเงาเกิน %d นาที", InpRoundLife_Min)); return; }

   int    stage = (act == SH_C4) ? 4 : g_rd.deepest;
   int    dir   = (act == SH_C4) ? -g_rd.dir : g_rd.dir;
   string why   = EntryBlockReason(ts, bid, ask);
   if(why == "" && !TradeAllowed()) why = "ปิด Algo Trading อยู่";
   if(why != "") { g_last_status = StringFormat("เงา: ถึงจุดเปิด %s แต่ติด %s (รอ)", StageTag(stage), why); return; }
   datetime now = ServerNow();
   if(now < g_next_try) return;
   ulong ticket = 0;
   if(OpenMarket(dir, stage, bid, ask, ticket)) {
      RoundOpened(g_rd, stage, msc);
      g_rd_pos = ticket;
      g_last_status = (act == SH_C4) ? "เงา: ราคาแตะ C4 → เปิดตามน้ำ"
                                     : StringFormat("เงา: ราคากลับถึง C1 → สวนด้วย Lot C%d (%s)", stage, StageTag(stage));
   } else g_next_try = now + 1;
}

// แท่งข่าว: ตามน้ำ 1 ไม้ต่อแท่ง
void LiveNewsStep(long msc, double bid, double ask) {
   if(g_news_traded_bar == g_zbar_time) return;
   int dir = NewsTrendDir(g_z_reg, g_z_sma);
   if(dir == 0) return;
   datetime now = ServerNow();
   if(now < g_next_try) return;
   ulong ticket = 0;
   if(OpenMarket(dir, ST_NEWS, bid, ask, ticket)) {
      g_news_traded_bar = g_zbar_time;
      LiveRoundBegin(RK_NEWS, dir, ST_NEWS, (dir == -1 ? bid : ask), ticket, msc);
      g_last_status = StringFormat("แท่งข่าว: เปิดตามน้ำ %s ที่ R %+.2f / S %+.2f", (dir == -1 ? "SELL" : "BUY"), g_z_reg, g_z_sma);
   } else g_next_try = now + 1;
}

// ว่าง (ไม่มีรอบ/ไม้): แท่งข่าว → ตามน้ำ, ตามน้ำปกติ, ไม่งั้นวาง Limit C1 ทั้งสองฝั่ง
void LiveIdleStep(long msc, int ts, double bid, double ask) {
   if(g_rd.kind != RK_NONE || OurPositionsTotal() > 0) {
      LiveDeleteLimits();
      g_idle_note = "⏸️ มีรอบ/ไม้ทำงานอยู่ (ทีละรอบ)";
      return;
   }
   string why = EntryBlockReason(ts, bid, ask);
   if(why == "" && !TradeAllowed()) why = "ปิด Algo Trading อยู่";
   if(why == "" && InBarStartDelay((datetime)(msc / 1000))) why = StringFormat("%d วิแรกของแท่ง", InpBarStartDelay_Sec);
   if(why != "") { LiveDeleteLimits(); g_idle_note = "⏳ ยังไม่วาง: " + why; return; }

   if(IsNewsBarT(g_zbar_time)) {
      LiveDeleteLimits();
      g_idle_note = "📰 แท่งข่าว → ปิดสวนกลับ ใช้ตามน้ำแทน";
      LiveNewsStep(msc, bid, ask);
      return;
   }

   int td = TrendNormalDir(g_z_reg, g_z_sma);
   if(td != 0) {
      if(!LiveDeleteLimits()) return;   // Limit เพิ่ง fill → ให้ LiveRoundSync รับเป็นรอบก่อน
      datetime now = ServerNow();
      if(now < g_next_try) return;
      ulong ticket = 0;
      if(OpenMarket(td, ST_TREND, bid, ask, ticket)) {
         LiveRoundBegin(RK_TREND, td, ST_TREND, (td == -1 ? bid : ask), ticket, msc);
         g_last_status = StringFormat("ตามน้ำปกติ: เปิด %s ที่ R %+.2f / S %+.2f", (td == -1 ? "SELL" : "BUY"), g_z_reg, g_z_sma);
      } else g_next_try = now + 1;
      return;
   }

   g_idle_note = "";
   EnsureLimit(-1, g_lim_s, g_lv.sell_ok, g_lv.sell_px, bid, ask);
   EnsureLimit( 1, g_lim_b, g_lv.buy_ok,  g_lv.buy_px,  bid, ask);
}

// เรียกทุก Tick และทุก 1 วินาที
void LiveStep(long msc, int ts, double bid, double ask) {
   LiveRoundSync(msc);
   if(!g_z_valid) return;
   LiveShadowStep(msc, ts, bid, ask);
   LiveIdleStep(msc, ts, bid, ask);
}

void CloseAllPositions() {
   DeleteOurPendings();
   g_lim_s = 0; g_lim_b = 0;
   if(g_rd.kind != RK_NONE) LiveRoundEnd("ใกล้ตลาดปิดสัปดาห์");
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
//   (Limit C1 ที่ระดับ Z / นาทีแรกของแท่ง / ระบบเงา R2-R3-C4 / ตามน้ำปกติ / แท่งข่าว / TP / SL / โล่ / ตัด 60 วิ / ปิดสุดสัปดาห์)
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
   int      stage;         // ST_NEWS / 1 C1 / 2 R2 / 3 R3 / 4 C4 / ST_TREND
   double   lot;
   double   p_in, sl, tp;
   double   zr, zs;
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

// บันไดเงาของแต่ละรอบสวนกลับ (สำหรับวาด)
struct RRound {
   long   msc_start;
   long   msc_end;
   int    dir;
   double c1;
   int    deepest;     // 1-3 (4 = แตะ C4)
   bool   done;
   bool   drawn_final;
};

RTrade     g_rt[];
RBlocked   g_rb[];
RRound     g_rds[];
int        g_rt_open      = -1;
int        g_rb_drawn     = 0;
int        g_rd_cur       = -1;

// รอบ / Limit C1 / ข่าว ใน Replay
RoundState g_rp_rd;
BarLevels  g_rp_lv;
bool       g_rp_arm_s     = false;   // มี Sell Limit C1 รออยู่ (วางไว้ตั้งแต่ tick ก่อนหน้า)
bool       g_rp_arm_b     = false;
datetime   g_rp_blk_s     = 0;       // แท่งที่มาร์กจุดแตะระดับแต่ไม่มี Limit แล้ว (ต่อฝั่ง)
datetime   g_rp_blk_b     = 0;
datetime   g_rp_news_bar  = 0;

MqlRates   g_rr[];
int        g_rp_b         = -1;
datetime   g_rp_bar_t     = 0;
ZCache     g_rp_zc;
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
   ArrayResize(g_rds, 0);
   ArrayResize(g_rr, 0);
   g_rt_open = -1; g_rb_drawn = 0; g_rd_cur = -1;
   RoundReset(g_rp_rd);
   g_rp_lv.sell_ok = false; g_rp_lv.buy_ok = false;
   g_rp_arm_s = false; g_rp_arm_b = false;
   g_rp_blk_s = 0; g_rp_blk_b = 0; g_rp_news_bar = 0;
   g_rp_b = -1; g_rp_bar_t = 0; g_rp_zc.ok = false;
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

// เข้าแท่งใหม่ (TF ของ Z): สร้างแคช Z + ระดับ Limit C1 ของแท่ง
void ReplayEnterBar(int b) {
   g_rp_b = b;
   if(g_rr[b].time == g_rp_bar_t) return;
   g_rp_bar_t = g_rr[b].time;
   g_rp_zc.ok = false;
   g_rp_arm_s = false; g_rp_arm_b = false;   // Limit เดิมถูกย้าย/ลบตอนขึ้นแท่งใหม่
   int n = InpZ_Period;
   if(b >= n) {
      double c[];
      ArrayResize(c, n);
      for(int i = 0; i < n; i++) c[i] = g_rr[b - n + i].close;
      BuildZCache(c, g_rp_zc);
   }
   ComputeLevels(g_rp_zc, g_rp_lv);
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
   double sl_d = PtsToPrice(stage != ST_NEWS ? InpSL_Pts : InpNewsSL_Pts);
   double tp_d = PtsToPrice(InpTP_Pts);
   g_rt[i].msc_in   = msc;
   g_rt[i].dir      = dir;
   g_rt[i].stage    = stage;
   g_rt[i].lot      = LotForStage(stage);
   g_rt[i].p_in     = price;
   g_rt[i].sl       = (sl_d > 0.0) ? ((dir == -1) ? price + sl_d : price - sl_d) : 0.0;
   g_rt[i].tp       = (stage != ST_NEWS) ? ((dir == -1) ? price - tp_d : price + tp_d) : 0.0;
   g_rt[i].zr       = g_rp_zr;
   g_rt[i].zs       = g_rp_zs;
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
   return i;
}

// เริ่มรอบใหม่ด้วยไม้แรกของรอบ (C1 / ข่าว / ตามน้ำปกติ)
void ReplayRoundBegin(int kind, int dir, int stage, long msc, double price) {
   ReplayOpen(dir, stage, msc, price);
   RoundBegin(g_rp_rd, kind, dir, stage, price, msc);
   g_rp_arm_s = false; g_rp_arm_b = false;
   if(kind != RK_COUNTER) return;
   int k = ArraySize(g_rds);
   ArrayResize(g_rds, k + 1);
   g_rds[k].msc_start = msc;   g_rds[k].msc_end = 0;
   g_rds[k].dir       = dir;   g_rds[k].c1      = price;
   g_rds[k].deepest   = 1;     g_rds[k].done    = false;
   g_rds[k].drawn_final = false;
   g_rd_cur = k;
}

void ReplayRoundEnd(long msc) {
   if(g_rd_cur >= 0) {
      g_rds[g_rd_cur].msc_end = msc;
      g_rds[g_rd_cur].done    = true;
      g_rd_cur = -1;
   }
   RoundReset(g_rp_rd);
}

// ปิดไม้จำลอง → รอบเดินต่อ (ชน SL รอเงา) หรือจบรอบ
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
   if(g_rp_rd.kind == RK_NONE) return;
   if(!RoundAfterClose(g_rp_rd, reason == RX_SL, msc_out)) ReplayRoundEnd(msc_out);
}

// เหตุการณ์ตามเวลาระหว่าง tick ก่อนหน้า → tick นี้ (ราคายังเป็นของ tick ก่อนหน้า)
void ReplayTimeEvents(long msc) {
   if(!g_rp_have) return;
   if(g_rt_open >= 0) {
      int  i   = g_rt_open;
      long wk  = (g_rt[i].force_close > 0) ? (long)g_rt[i].force_close * 1000 : LONG_MAX;
      long cut = (g_rt[i].stage != ST_NEWS && InpQuickWindow_Sec > 0 && !g_rt[i].activated)
                 ? g_rt[i].msc_in + (long)InpQuickWindow_Sec * 1000 : LONG_MAX;
      double px = (g_rt[i].dir == -1) ? g_rp_ask : g_rp_bid;
      if(wk <= cut && wk <= msc)       ReplayClose(wk,  px, RX_WEEK);
      else if(cut < wk && cut <= msc)  ReplayClose(cut, px, RX_CUT);
   }
   if(RoundExpired(g_rp_rd, msc)) ReplayRoundEnd(g_rp_rd.evt_msc + (long)InpRoundLife_Min * 60000);
}

// ไม้ที่ถืออยู่: SL / TP / โล่ ด้วยราคา tick ปัจจุบัน
void ReplayManageTick(long msc, double bid, double ask) {
   int i = g_rt_open;
   if(i < 0) return;
   int d = g_rt[i].dir;
   if(d == -1) {
      if(g_rt[i].sl > 0.0 && ask >= g_rt[i].sl) { ReplayClose(msc, ask, g_rt[i].activated ? RX_TRAIL : RX_SL); return; }
      if(g_rt[i].tp > 0.0 && ask <= g_rt[i].tp) { ReplayClose(msc, g_rt[i].tp, RX_TP); return; }
   } else {
      if(g_rt[i].sl > 0.0 && bid <= g_rt[i].sl) { ReplayClose(msc, bid, g_rt[i].activated ? RX_TRAIL : RX_SL); return; }
      if(g_rt[i].tp > 0.0 && bid >= g_rt[i].tp) { ReplayClose(msc, g_rt[i].tp, RX_TP); return; }
   }
   double prof = (d == -1) ? (g_rt[i].p_in - ask) : (bid - g_rt[i].p_in);
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

// ระบบเงาของรอบสวนกลับ: จำระดับลึกสุด / สวนที่ C1 ด้วย Lot ระดับลึกสุด / แตะ C4 ตามน้ำ
void ReplayShadowTick(long msc, int ts, double bid, double ask) {
   if(g_rp_rd.kind != RK_COUNTER) return;
   RoundTrack(g_rp_rd, bid, ask, msc);
   if(g_rd_cur >= 0 && g_rds[g_rd_cur].deepest < g_rp_rd.deepest) g_rds[g_rd_cur].deepest = g_rp_rd.deepest;
   int act = RoundShadowAction(g_rp_rd, bid, ask, msc);
   if(act == SH_NONE) return;
   if(act == SH_EXPIRE) { ReplayRoundEnd(msc); return; }
   if(EntryBlockReason(ts, bid, ask) != "") return;   // ติดตัวกรอง → รอ tick ถัดไป
   int stage = (act == SH_C4) ? 4 : g_rp_rd.deepest;
   int dir   = (act == SH_C4) ? -g_rp_rd.dir : g_rp_rd.dir;
   ReplayOpen(dir, stage, msc, (dir == -1) ? bid : ask);
   RoundOpened(g_rp_rd, stage, msc);
   if(act == SH_C4 && g_rd_cur >= 0) g_rds[g_rd_cur].deepest = 4;
}

// มาร์กจุดที่ราคาแตะระดับ C1 ตอนว่างแต่ไม่มี Limit รออยู่ (1 ครั้ง/แท่ง/ฝั่ง)
void ReplayBlock(long msc, int dir, double price, string why) {
   if(dir == -1) { if(g_rp_blk_s == g_rp_bar_t) return; g_rp_blk_s = g_rp_bar_t; }
   else          { if(g_rp_blk_b == g_rp_bar_t) return; g_rp_blk_b = g_rp_bar_t; }
   int k = ArraySize(g_rb);
   ArrayResize(g_rb, k + 1);
   g_rb[k].msc = msc; g_rb[k].dir = dir; g_rb[k].price = price; g_rb[k].why = why;
}

void ReplayTick(const MqlTick &tk) {
   double bid = tk.bid, ask = tk.ask;
   if(bid <= 0.0 || ask <= 0.0) return;
   long     msc = (long)tk.time_msc;
   datetime t   = (datetime)(msc / 1000);

   ReplayTimeEvents(msc);                 // A) เหตุการณ์ตามเวลาด้วยราคาเดิม
   if(!ReplayBarFor(t)) return;           // B) แท่งของ tick นี้ (ขึ้นแท่งใหม่ → ระดับ C1 ใหม่)
   bool news_bar = IsNewsBarT(g_rp_bar_t);
   int  ts       = GetTimeStateAt(t);

   double zr = 0.0, zs = 0.0, fit, sig, mn, ssd;
   bool   fl;
   bool   zok = ZAtPrice(g_rp_zc, bid, zr, zs, fit, sig, fl, mn, ssd);
   if(zok) { g_rp_zr = zr; g_rp_zs = zs; }

   if(g_rt_open >= 0) ReplayManageTick(msc, bid, ask);   // C) ไม้ที่ถืออยู่
   ReplayShadowTick(msc, ts, bid, ask);                  // D) ระบบเงา

   // E) ว่าง: Limit C1 ที่วางไว้ตั้งแต่ tick ก่อนหน้าถูก fill? (gap → ได้ราคาที่ดีกว่า)
   bool idle = (g_rp_rd.kind == RK_NONE && g_rt_open < 0);
   if(idle && g_rp_arm_s && bid >= g_rp_lv.sell_px)     { ReplayRoundBegin(RK_COUNTER, -1, 1, msc, MathMax(g_rp_lv.sell_px, bid)); idle = false; }
   else if(idle && g_rp_arm_b && ask <= g_rp_lv.buy_px) { ReplayRoundBegin(RK_COUNTER,  1, 1, msc, MathMin(g_rp_lv.buy_px, ask)); idle = false; }

   // F) สัญญาณใหม่ (ข่าว / ตามน้ำปกติ) + สถานะ Limit C1 สำหรับ tick ถัดไป
   bool   early = InBarStartDelay(t);
   string why   = EntryBlockReason(ts, bid, ask);
   bool   allow = idle && zok && !early && why == "";
   if(allow && news_bar) {
      if(g_rp_news_bar != g_rp_bar_t) {
         int nd = NewsTrendDir(zr, zs);
         if(nd != 0) {
            ReplayRoundBegin(RK_NEWS, nd, ST_NEWS, msc, (nd == -1) ? bid : ask);
            g_rp_news_bar = g_rp_bar_t;
         }
      }
      allow = false;
   }
   if(allow) {
      int td = TrendNormalDir(zr, zs);
      if(td != 0) { ReplayRoundBegin(RK_TREND, td, ST_TREND, msc, (td == -1) ? bid : ask); allow = false; }
   }
   bool still_idle = (g_rp_rd.kind == RK_NONE && g_rt_open < 0);
   g_rp_arm_s = allow && g_rp_lv.sell_ok && bid < g_rp_lv.sell_px;
   g_rp_arm_b = allow && g_rp_lv.buy_ok  && ask > g_rp_lv.buy_px;

   if(still_idle && zok && !news_bar) {
      string w = early ? "นาทีแรกของแท่ง" : (why != "" ? why : "ราคาเลยระดับตั้งแต่ก่อนวาง Limit (รอกลับ)");
      if(g_rp_lv.sell_ok && bid >= g_rp_lv.sell_px) ReplayBlock(msc, -1, bid, w);
      if(g_rp_lv.buy_ok  && ask <= g_rp_lv.buy_px)  ReplayBlock(msc,  1, ask, w);
   }

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
   if(g_rt[i].stage == 2 || g_rt[i].stage == 3)
      tipText += StringFormat(" | เงา: กลับเข้าที่ C1 ด้วย Lot ของ C%d", g_rt[i].stage);
   else if(g_rt[i].stage == 4)        tipText += " | เงา: ราคาแตะ C4 → ตามน้ำ";
   else if(g_rt[i].stage == ST_TREND) tipText += " | ตามน้ำปกติ";
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
   if(InpShowLadder)
      for(int k = 0; k < ArraySize(g_rds); k++) {
         if(g_rds[k].drawn_final) continue;
         long end = g_rds[k].done ? g_rds[k].msc_end : g_rp_msc;
         DrawLadder("R" + IntegerToString(g_rds[k].msc_start), g_rds[k].dir, g_rds[k].c1,
                    (datetime)(g_rds[k].msc_start / 1000), (datetime)(end / 1000), g_rds[k].deepest);
         g_rds[k].drawn_final = g_rds[k].done;
      }
   if(InpShowReplayBlocked)
      for(; g_rb_drawn < ArraySize(g_rb); g_rb_drawn++) DrawReplayBlocked(g_rb_drawn);
}

string ReplayStatsText() {
   if(!InpShowReplay) return "";
   int    n = 0, w = 0, c_tp = 0, c_sl = 0, c_cut = 0, c_tr = 0, c_wk = 0;
   int    cnt[6];
   double usd_st[6];
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
      int st = MathMax(0, MathMin(5, g_rt[i].stage));
      cnt[st]++;
      usd_st[st] += g_rt[i].usd;
      switch(g_rt[i].reason) {
         case RX_TP: c_tp++; break;   case RX_SL: c_sl++; break;   case RX_CUT: c_cut++; break;
         case RX_TRAIL: c_tr++; break; case RX_WEEK: c_wk++; break;
      }
   }
   string s = StringFormat("🧪 Replay %d วัน: %s\n   %d ไม้ / %d รอบสวน | ชนะ %.0f%% | กำไรสุทธิ $%+.2f | DD $%.2f | TP %d SL %d ตัด60วิ %d โล่ %d ปิดสัปดาห์ %d | แตะระดับแต่ไม่มี Limit %d",
                           InpReplayDays, g_rp_status, n, ArraySize(g_rds), (n > 0 ? 100.0 * w / n : 0.0), usd, dd,
                           c_tp, c_sl, c_cut, c_tr, c_wk, ArraySize(g_rb));
   s += StringFormat("\n   ตามลำดับไม้: C1 %d ($%+.2f) | R2 %d ($%+.2f) | R3 %d ($%+.2f) | C4 %d ($%+.2f) | ตามน้ำ %d ($%+.2f) | ข่าว %d ($%+.2f)%s",
                     cnt[1], usd_st[1], cnt[2], usd_st[2], cnt[3], usd_st[3], cnt[4], usd_st[4], cnt[5], usd_st[5], cnt[0], usd_st[0],
                     (g_rt_open >= 0 ? " | มีไม้จำลองถืออยู่" : (g_rp_rd.kind == RK_COUNTER ? " | รอบเงาจำลองรออยู่" : "")));
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
   if(g_rp_caught) ReplayTimeEvents(now_msc);   // เวลาผ่านไปโดยไม่มี tick (ตัด 60 วิ / รอบเงาหมดอายุ)

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
// 📏 เส้นระดับ Limit C1 รายแท่ง + บันไดเงา C1-C4
//====================================================================
string   g_lvl_names[];
datetime g_lvl_times[];
datetime g_lvl_bar = 0;   // แท่งปัจจุบัน (TF ของ Z) ตอนวาดล่าสุด

void SetLevelSeg(string name, datetime t, double px, bool show, color clr, string tip) {
   if(!show) { if(ObjectFind(0, name) >= 0) ObjectDelete(0, name); return; }
   datetime t2 = t + (datetime)PeriodSeconds(InpZ_Timeframe);
   if(ObjectFind(0, name) < 0) {
      ObjectCreate(0, name, OBJ_TREND, 0, t, px, t2, px);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      int n = ArraySize(g_lvl_names);
      ArrayResize(g_lvl_names, n + 1);
      ArrayResize(g_lvl_times, n + 1);
      g_lvl_names[n] = name;
      g_lvl_times[n] = t;
   }
   ObjectMove(0, name, 0, t,  px);
   ObjectMove(0, name, 1, t2, px);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, tip);
}

void DrawLevelBar(datetime t, const BarLevels &lv) {
   string ts = IntegerToString((long)t);
   string tt = TimeToString(t, TIME_DATE|TIME_MINUTES);
   SetLevelSeg(OBJ_PREFIX + "LV_S_" + ts, t, lv.sell_px, lv.sell_ok, InpClrC1Sell,
               StringFormat("Limit C1 SELL แท่ง %s @ %s (%s ≥ +%.2f)", tt, DoubleToString(lv.sell_px, _Digits), LogicName(), InpSellZ));
   SetLevelSeg(OBJ_PREFIX + "LV_B_" + ts, t, lv.buy_px, lv.buy_ok, InpClrC1Buy,
               StringFormat("Limit C1 BUY แท่ง %s @ %s (%s ≤ −%.2f)", tt, DoubleToString(lv.buy_px, _Digits), LogicName(), InpBuyZ));
}

// เรียกทุก 1 วินาที: ครั้งแรกวาดย้อนหลัง InpLevelBars แท่ง, ขึ้นแท่งใหม่วาดแท่งใหม่ + ลบแท่งที่หลุดช่วง
void UpdateLevelLines() {
   if(!g_draw || !InpShowC1Levels || !g_z_ready) return;
   datetime t0 = CurrentZBarTime();
   if(t0 == 0 || t0 == g_lvl_bar) return;
   int n = InpZ_Period;
   if(g_lvl_bar == 0) {
      int cnt = InpLevelBars + n;
      double   c[];
      datetime tt[];
      if(CopyClose(_Symbol, InpZ_Timeframe, 1, cnt, c) != cnt || CopyTime(_Symbol, InpZ_Timeframe, 1, cnt, tt) != cnt) return;
      double    s[];
      ZCache    zc;
      BarLevels lv;
      ArrayResize(s, n);
      for(int j = n; j < cnt; j++) {   // แท่ง j ใช้ราคาปิด n แท่งก่อนหน้า (เหมือนตอนแท่งนั้นยังไม่ปิด)
         ArrayCopy(s, c, 0, j - n, n);
         BuildZCache(s, zc);
         ComputeLevels(zc, lv);
         DrawLevelBar(tt[j], lv);
      }
   }
   else {
      datetime cutoff = iTime(_Symbol, InpZ_Timeframe, InpLevelBars);
      int m = ArraySize(g_lvl_names), w = 0;
      for(int i = 0; i < m; i++) {
         if((cutoff > 0 && g_lvl_times[i] < cutoff) || ObjectFind(0, g_lvl_names[i]) < 0) {
            ObjectDelete(0, g_lvl_names[i]);
            continue;
         }
         g_lvl_names[w] = g_lvl_names[i];
         g_lvl_times[w] = g_lvl_times[i];
         w++;
      }
      if(w != m) { ArrayResize(g_lvl_names, w); ArrayResize(g_lvl_times, w); }
   }
   DrawLevelBar(t0, g_lv);
   g_lvl_bar = t0;
}

// บันไดเงาของรอบ: C1 (เส้นทึบ) + C2 / C3 / C4 (เส้นจุด) จากเวลาเริ่มถึงเวลาจบรอบ — ระดับที่ราคาแตะแล้วเส้นหนา
void DrawLadder(string id, int dir, double c1, datetime t1, datetime t2, int deepest) {
   if(!g_draw || !InpShowLadder) return;
   if(t2 <= t1) t2 = t1 + 60;
   int top = InpShadowEnable ? 4 : 1;
   for(int lv = 1; lv <= top; lv++) {
      double px = c1 - dir * LadderDist(lv);
      string nm = OBJ_PREFIX + "LD_" + id + "_" + IntegerToString(lv);
      if(ObjectFind(0, nm) < 0) {
         ObjectCreate(0, nm, OBJ_TREND, 0, t1, px, t2, px);
         ObjectSetInteger(0, nm, OBJPROP_COLOR, InpClrLadder);
         ObjectSetInteger(0, nm, OBJPROP_STYLE, (lv == 1) ? STYLE_SOLID : STYLE_DOT);
         ObjectSetInteger(0, nm, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
      }
      ObjectMove(0, nm, 1, t2, px);
      ObjectSetInteger(0, nm, OBJPROP_WIDTH, (lv <= deepest) ? 2 : 1);
      string what = (lv == 1) ? "C1 (จุดยึด / จุดสวนกลับ)"
                  : (lv == 4) ? StringFormat("C4 (แตะ = ตามน้ำ Lot %.2f)", LotForStage(4))
                              : StringFormat("C%d (กลับ C1 = สวน Lot %.2f)", lv, LotForStage(lv));
      ObjectSetString(0, nm, OBJPROP_TOOLTIP, StringFormat("รอบ %s %s: %s @ %s%s", (dir == -1 ? "SELL" : "BUY"),
                      TimeToString(t1, TIME_DATE|TIME_MINUTES), what, DoubleToString(px, _Digits), (lv <= deepest ? " ✓ ราคาแตะแล้ว" : "")));
   }
}

// บันไดของรอบจริง (วาดเมื่อไม่ได้เปิด Tick Replay — ไม่งั้น Replay วาดรอบเดียวกันให้แล้ว)
void DrawLiveLadder(datetime t_end) {
   if(InpShowReplay || g_rd.kind != RK_COUNTER) return;
   DrawLadder("L" + IntegerToString(g_rd.start_msc), g_rd.dir, g_rd.c1, (datetime)(g_rd.start_msc / 1000), t_end, g_rd.deepest);
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
   string rs   = RoundShortText();
   if(rs != "") text = rs + "  |  " + text;

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

string LevelText(int dir, double bid, double ask) {
   if(!g_z_ready) return "รอข้อมูลแท่งเทียน...";
   bool   ok = (dir == -1) ? g_lv.sell_ok : g_lv.buy_ok;
   double px = (dir == -1) ? g_lv.sell_px : g_lv.buy_px;
   ulong  tk = (dir == -1) ? g_lim_s : g_lim_b;
   if(!ok) return "— Z ไปไม่ถึงเกณฑ์ในแท่งนี้ (ไม่วาง Limit)";
   double dist = PriceToPts((dir == -1) ? (px - bid) : (ask - px));
   string s    = StringFormat("ระดับ %s (ห่าง %.0f จุด)", DoubleToString(px, _Digits), dist);
   if(tk != 0 && OrderSelect(tk)) return "📌 Limit วางอยู่ " + s;
   if(g_idle_note != "") return s + " | " + g_idle_note;
   if(dist <= 0.0)       return s + " | ⏳ ราคาเลยระดับ → รอกลับก่อนวาง Limit";
   return s + " | ⏳ กำลังวาง Limit";
}

string TrendText() {
   if(!InpTrendEnable) return "ปิด";
   int d = g_z_valid ? TrendNormalDir(g_z_reg, g_z_sma) : 0;
   return StringFormat("|Z_reg| > %.2f และ Z_SMA ทิศเดียวกันอยู่ใน %.2f–%.2f%s", InpTrendZR, InpTrendSmaMin, InpTrendSmaMax,
                       (d == 1 ? " | ✓ เข้าเงื่อนไข BUY" : (d == -1 ? " | ✓ เข้าเงื่อนไข SELL" : "")));
}

string RoundText(datetime now) {
   string side = (g_rd.dir == -1) ? "SELL" : "BUY";
   if(g_rd.kind == RK_NONE)  return "ว่าง — รอ Limit C1 / ตามน้ำ";
   if(g_rd.kind == RK_NEWS)  return "📰 ไม้ข่าวตามน้ำ " + side;
   if(g_rd.kind == RK_TREND) return "📈 ไม้ตามน้ำปกติ " + side;
   string s = StringFormat("%s รอบ %s | C1 %s", (g_rd.dir == -1 ? "🔻" : "🔺"), side, DoubleToString(g_rd.c1, _Digits));
   if(InpShadowEnable)
      s += StringFormat(" | C2 %s / C3 %s / C4 %s | ลึกสุด C%d", DoubleToString(LadderPrice(g_rd, 2), _Digits),
                        DoubleToString(LadderPrice(g_rd, 3), _Digits), DoubleToString(LadderPrice(g_rd, 4), _Digits), g_rd.deepest);
   if(g_rd.in_pos) return s + " | ถือ " + StageTag(g_rd.stage);
   long left = (long)InpRoundLife_Min * 60 - (MathMax(g_last_tick_msc, (long)now * 1000) - g_rd.evt_msc) / 1000;
   if(g_rd.deepest > g_rd.used) s += StringFormat(" | 👻 รอกลับ C1 → สวน Lot C%d", g_rd.deepest);
   else if(g_rd.used < 3)       s += StringFormat(" | 👻 ต้องไปถึง C%d ก่อนถึงจะสวนซ้ำได้", g_rd.used + 1);
   else                         s += " | 👻 รอแตะ C4 (ตามน้ำ)";
   return s + " | หมดอายุอีก " + FormatDuration(left);
}

string RoundShortText() {
   if(g_rd.kind == RK_NONE) return "";
   string side = (g_rd.dir == -1) ? "SELL" : "BUY";
   if(g_rd.kind == RK_COUNTER) return StringFormat("รอบ %s ลึก C%d%s", side, g_rd.deepest, (g_rd.in_pos ? "" : " 👻"));
   return ((g_rd.kind == RK_NEWS) ? "NEWS " : "TREND ") + side;
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

   string msg = StringFormat("=== 📊 7-Lines Counter EA v9.00 (เข้าไม้: %s | C1 = Limit ที่ระดับ Z | เงา %s | ตามน้ำปกติ %s | ข่าวตามน้ำ %s) ===\n",
                             LogicName(), (InpShadowEnable ? "เปิด" : "ปิด"), (InpTrendEnable ? "เปิด" : "ปิด"), (InpUseNewsTrend ? "เปิด" : "ปิด"));
   msg += StringFormat("Z (%s, %d) : %s\n", EnumToString(InpZ_Timeframe), InpZ_Period, z_str);
   msg += StringFormat("Z แท่งที่เพิ่งปิด : R %+.2f / S %+.2f%s\n", g_prev_close_zr, g_prev_close_zs, (news_str == "" ? "" : " | " + news_str));
   msg += StringFormat("C1 SELL (Z ≥ +%.2f) : %s\n", InpSellZ, LevelText(-1, bid, ask));
   msg += StringFormat("C1 BUY  (Z ≤ −%.2f) : %s\n", InpBuyZ,  LevelText( 1, bid, ask));
   msg += "ตามน้ำปกติ : " + TrendText() + "\n";
   msg += StringFormat("ออเดอร์ : BUY %d / SELL %d | สเปรด %.0f / %.0f จุด\n",
                       buys, sells, PriceToPts(ask - bid), InpMaxSpread_Pts);
   msg += "รอบ : " + RoundText(now) + "\n";
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
   if(InpLevelBars < 1 || InpLevelBars > 2000) { Print("❌ InpLevelBars ต้องอยู่ระหว่าง 1-2000"); return(INIT_PARAMETERS_INCORRECT); }
   if(InpReplayDays < 1 || InpReplayDays > 60) { Print("❌ InpReplayDays ต้องอยู่ระหว่าง 1-60"); return(INIT_PARAMETERS_INCORRECT); }
   if(InpSellZ <= 0.0 || InpBuyZ <= 0.0) { Print("❌ ค่า Z ไม่ถูกต้อง"); return(INIT_PARAMETERS_INCORRECT); }
   if(InpLot <= 0.0) { Print("❌ Lot ไม่ถูกต้อง"); return(INIT_PARAMETERS_INCORRECT); }
   if(InpTP_Pts <= 0.0 || InpSL_Pts <= 0.0 || InpTrailDist_Pts <= 0.0 || InpTrailInterval_Sec < 1) {
      Print("❌ TP / SL / ระยะโล่ / รอบไล่จี้ ไม่ถูกต้อง");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpQuickWindow_Sec < 0) {
      Print("❌ เวลาตัดจบต้องไม่ติดลบ");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpSigmaFloorMult < 0.0 || InpBarStartDelay_Sec < 0 || InpLotStep < 0.0 || InpRoundLife_Min < 1 ||
      InpShadowC2_Pts <= 0.0 || InpShadowC3_Pts <= InpShadowC2_Pts || InpShadowC4_Pts <= InpShadowC3_Pts ||
      InpNewsTrendZ <= 0.0 || InpNewsSL_Pts < 0.0) {
      Print("❌ ค่าพื้นตัวหาร / เวลาต้นแท่ง / ระบบเงา (ต้อง 0 < C2 < C3 < C4) / ข่าว ไม่ถูกต้อง");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpTrendZR <= 0.0 || InpTrendSmaMin < 0.0 || InpTrendSmaMax < InpTrendSmaMin) {
      Print("❌ ค่าโหมดตามน้ำปกติไม่ถูกต้อง (ต้อง ZR > 0 และ 0 ≤ SmaMin ≤ SmaMax)");
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

   g_last_tick_msc = 0;
   g_zc.ok         = false;
   g_lv.sell_ok    = false;
   g_lv.buy_ok     = false;
   ReplayReset();
   g_zbar_time      = 0;
   g_z_ready        = false;
   g_blk_valid      = false;
   g_last_trail     = 0;
   g_next_try       = 0;
   g_news_loaded    = 0;
   g_news_traded_bar = 0;
   RoundReset(g_rd);
   g_rd_pos         = 0;
   g_lim_s          = 0;
   g_lim_b          = 0;
   g_idle_note      = "";
   g_prev_close_zr  = 0.0;
   g_prev_close_zs  = 0.0;
   ArrayResize(g_seg_times, 0);
   ArrayResize(g_marks, 0);
   g_marks_bar = 0;
   g_lvl_bar   = 0;
   ArrayResize(g_lvl_names, 0);
   ArrayResize(g_lvl_times, 0);
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
   DeleteOurPendings();   // Limit ค้างจากรอบก่อน (สถานะรอบไม่ถูกเก็บข้ามการรีสตาร์ท)

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
   LiveStep(g_last_tick_msc, ts, tk.bid, tk.ask);
}

void OnTimer() {
   datetime now = ServerNow();
   int ts = GetTimeState(now);
   RefreshNews(now);

   // 1. บังคับปิดก่อนตลาดปิดสัปดาห์ / จัดการไม้ (เปิดไล่จี้, ตัดจบตามเวลา, ขยับโล่)
   if(ts == TS_CLOSING)     CloseAllPositions();
   else if(ts != TS_CLOSED) ManagePositions(now);

   // 2. รอบ / เงา / Limit C1 แม้ไม่มี Tick เข้า (ราคา/Z ยังเป็นค่าล่าสุด)
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   bool   px_ok = (bid > 0.0 && ask > 0.0);
   if(px_ok) UpdateZ(bid);
   long   msc   = MathMax(g_last_tick_msc, (long)now * 1000);
   if(ts != TS_CLOSING) { if(px_ok) LiveStep(msc, ts, bid, ask); else LiveRoundSync(msc); }

   // 3. อัปเดตการแสดงผล
   if(g_draw) {
      UpdateZLines();
      UpdateLinesLive();
      UpdateBarZLabels();
      UpdateLevelLines();
      UpdateEntryMarks();
      ReplayStep();
      LoadNewsHistory();
      DrawLiveLadder(now);
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
   LiveRoundSync(MathMax(g_last_tick_msc, (long)ServerNow() * 1000));   // Limit C1 fill / ไม้ของรอบปิด → อัปเดตรอบทันที
}
//+------------------------------------------------------------------+
