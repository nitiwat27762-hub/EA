//+------------------------------------------------------------------+
//|                                       Seven_Lines_Wall_Ind.mq5   |
//|      Wall Confluence Zones + VRVP for XAUUSD (แสดงผลอย่างเดียว)     |
//+------------------------------------------------------------------+
//
// 🎯 หน้าที่ (แปลงจาก Seven_Lines_Wall_EA v1.00 — ไม่ส่งคำสั่งเทรด)
//  ผลทดสอบ Wall EA: กำแพงเดี่ยวไม่มีนัยสำคัญ (W1 = 79% ของกำแพง, คะแนนแยกไม่ออก) → แสดงเฉพาะ "จุดที่ซ้อนกันเยอะ" + VRVP
//  (ประวัติการเปลี่ยนแปลงอยู่ใน README.md)
//
// 🧱 กำแพง W1-W6 (สร้างใหม่ทุกแท่งของ TF ของ Z จากแท่งที่ปิดแล้ว — สูตรเดียวกับ Wall EA)
//  • W1 ยอดของจุด A ในอดีต: High / Low ของแท่งที่ Z ตรงนั้น > 2.0 (5 วัน)
//  • W2 High / Low ของวันก่อน + ช่วง Asia / London ล่าสุดที่จบแล้ว (เวลาเซิร์ฟเวอร์)
//  • W3 ตัวเลขกลมทุก $10 | W4 Swing H1 (fractal 2, 3 วัน)
//  • W5 ราคาที่ tick หนาแน่น 24 ชม. (5 ยอด) | W6 ราคาที่ทำให้ Z* = ±6 / ±8
//
// 🟧 โซนซ้อน (Confluence)
//  • เรียงกำแพงตามราคา → หน้าต่างกว้าง 500 จุด ที่มีกำแพง "ต่างชนิดกัน" ≥ 3 ชนิด = 1 โซน (แถบสี)
//  • สีเข้มขึ้นตามจำนวนชนิดที่ซ้อน (3 / 4 / 5+), ชี้ที่แถบ = รายชื่อกำแพงทั้งหมดในโซน
//
// 📊 VRVP (Visible Range Volume Profile)
//  • ช่วงแท่งที่มองเห็นบนกราฟ → tick volume ของแท่ง M1 กระจายเท่ากันตลอด High-Low ของแท่ง → ช่องละ 200 จุด
//    (ช่วงกว้างมากจนเกิน 50,000 แท่ง M1 → ใช้ M5 / M15 / H1 แทนอัตโนมัติ)
//  • แท่งนอนชิดขอบขวา กว้างสุด 25% ของกราฟ | POC = ช่องที่ volume สูงสุด | Value Area 70% รอบ POC
//  • คำนวณใหม่เมื่อเลื่อน / ซูม / ย่อขยายกราฟ และทุก 2 วินาทีเมื่อกราฟอยู่ที่แท่งล่าสุด
//
#property copyright   "Commander's Quant System"
#property version     "1.00"
#property description "แสดงโซนกำแพงซ้อน (W1-W6 ≥ 3 ชนิดในระยะ 500 จุด) + VRVP สำหรับ XAUUSD (Indicator แสดงผลอย่างเดียว)"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

//====================================================================
// 🎛️ INPUT PARAMETERS
//====================================================================
input group "=== 1. Z-Score (ใช้สร้าง W1 / W6) ==="
input ENUM_TIMEFRAMES InpZ_Timeframe       = PERIOD_M15; // Timeframe ที่ใช้คำนวณ Z / สร้างกำแพง
input int             InpZ_Period          = 20;         // จำนวนแท่งของ SMA / StdDev
input double          InpSigmaFloorMult    = 0.50;       // ตัวหาร Z_reg ต้องไม่น้อยกว่า ค่านี้ × StdDev ของการเปลี่ยนแปลงราคาต่อแท่ง
input double          InpA_Z               = 2.00;       // W1: แท่งที่ Z_reg หรือ Z_SMA ที่ High / Low > ค่านี้

input group "=== 2. กำแพง ==="
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
input double          InpTouch_Pts         = 200.0;      // คะแนน (ใน tooltip): แตะกำแพง = ราคาห่างไม่เกินกี่จุด
input int             InpTouchDays         = 3;          // คะแนน (ใน tooltip): นับแท่งที่แตะแล้วไม่ทะลุย้อนหลังกี่วัน
input double          InpConf_Pts          = 500.0;      // คะแนน (ใน tooltip): นับกำแพงอื่นในระยะกี่จุด

input group "=== 3. โซนซ้อน ==="
input bool            InpShowZones         = true;       // แสดงโซนกำแพงซ้อน
input double          InpZoneWidth_Pts     = 500.0;      // กำแพงที่อยู่ในหน้าต่างกว้างกี่จุด นับเป็นโซนเดียวกัน
input int             InpZoneMinTypes      = 3;          // โซนต้องมีกำแพงต่างชนิดกันอย่างน้อยกี่ชนิด (W1-W6)
input double          InpZonePad_Pts       = 100.0;      // ขยายแถบโซนขึ้น / ลงกี่จุด (ให้มองเห็นแม้กำแพงอยู่ราคาเดียวกัน)
input int             InpZoneBarsRight     = 8;          // แถบโซนยื่นไปทางขวาของแท่งปัจจุบันกี่แท่ง (TF ของ Z)
input bool            InpShowWallLines     = false;      // แสดงเส้นกำแพงเดี่ยวทุกเส้นด้วย (เส้นจุดบาง)

input group "=== 4. VRVP ==="
input bool            InpShowVRVP          = true;       // แสดง Volume Profile ของช่วงที่มองเห็น
input double          InpVP_Bin_Pts        = 200.0;      // ขนาดช่องราคา (จุด)
input double          InpVP_WidthPct       = 25.0;       // ความกว้างสูงสุด (% ของความกว้างกราฟ)
input double          InpVP_ValueAreaPct   = 70.0;       // Value Area (% ของ volume รอบ POC)
input int             InpVP_MinRowPx       = 2;          // ความสูงขั้นต่ำต่อแถว (พิกเซล) — ช่องเล็กกว่านี้รวมแถวอัตโนมัติ

input group "=== 5. สี ==="
input color           InpClrZone3          = C'70,55,25';       // โซนซ้อน 3 ชนิด
input color           InpClrZone4          = C'120,80,20';      // โซนซ้อน 4 ชนิด
input color           InpClrZone5          = C'170,95,15';      // โซนซ้อน 5 ชนิดขึ้นไป
input color           InpClrZoneText       = clrGold;           // ป้ายโซน
input color           InpClrW1             = clrOrangeRed;      // เส้นกำแพง W1
input color           InpClrW2             = clrGold;           // เส้นกำแพง W2
input color           InpClrW3             = clrSilver;         // เส้นกำแพง W3
input color           InpClrW4             = clrMediumOrchid;   // เส้นกำแพง W4
input color           InpClrW5             = clrDodgerBlue;     // เส้นกำแพง W5
input color           InpClrW6             = clrMediumSeaGreen; // เส้นกำแพง W6
input color           InpClrVP             = C'60,70,90';       // VRVP: แถวนอก Value Area
input color           InpClrVPValue        = C'70,110,160';     // VRVP: แถวใน Value Area
input color           InpClrVPPoc          = clrGold;           // VRVP: แถว POC + เส้น POC
input color           InpClrVPEdge         = clrSteelBlue;      // VRVP: เส้น VAH / VAL

//====================================================================
// 🔒 INTERNAL
//====================================================================
#define NW 6   // ชนิดกำแพง W1-W6 (index 0-5)

const string OBJ_PREFIX = "7LWI_";
const long   DAY_SEC    = 86400;

struct Wall {
   double   px;
   int      type;       // 0-5 = W1-W6
   int      sub;        // W2: 1 PDH 2 PDL 3 Asia H 4 Asia L 5 London H 6 London L | W1 / W4: 1 High 2 Low | W6: ±ระดับ Z*
   datetime t;          // เวลาที่เกิด
   int      touches;    // แท่งที่แตะแล้วไม่ทะลุ
   int      conf;       // กำแพงอื่นในระยะ InpConf_Pts
};

double   g_pmult      = 1.0;
color    g_wclr[NW];
Wall     g_walls[];
datetime g_wall_bar   = 0;     // แท่ง (TF ของ Z) ที่สร้างกำแพงล่าสุด
string   g_zone_objs[];
int      g_vp_rows    = 0;     // จำนวนแถว VRVP ที่วาดอยู่ (ใช้ชื่อวัตถุซ้ำ ไม่ลบ-สร้างใหม่ทุกรอบ)
string   g_vp_sig     = "";    // สถานะกราฟตอนวาด VRVP ล่าสุด
uint     g_vp_last_ms = 0;

//====================================================================
// 🧰 HELPERS
//====================================================================
double PtsToPrice(double pts) { return pts * g_pmult * _Point; }
double PriceToPts(double px)  { return px / (g_pmult * _Point); }

datetime CurrentZBarTime() { return iTime(_Symbol, InpZ_Timeframe, 0); }

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
// 🧮 Z (สูตรเดียวกับ Counter EA)
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
// 🧱 กำแพง W1-W6 — สร้างจากแท่ง r[0..b−1] ที่ปิดแล้ว (b = แท่งปัจจุบัน)
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

// สร้างกำแพงใหม่เมื่อขึ้นแท่งใหม่ (TF ของ Z) — true = มีการเปลี่ยนแปลง
bool RebuildWalls() {
   datetime t0 = CurrentZBarTime();
   if(t0 == 0 || t0 == g_wall_bar) return false;
   int per_day = (int)(DAY_SEC / MathMax(60, PeriodSeconds(InpZ_Timeframe)));
   int days    = MathMax(MathMax(InpW1_Days, InpW4_Days), MathMax(InpTouchDays, 2)) + 2;
   int cnt     = days * per_day + InpZ_Period + 5;
   MqlRates r[];
   int got = CopyRates(_Symbol, InpZ_Timeframe, 0, cnt, r);
   if(got <= InpZ_Period + 3 || r[got - 1].time != t0) return false;   // ประวัติยังโหลดไม่ครบ → ลองใหม่รอบหน้า
   BuildWalls(r, got - 1, g_walls);
   g_wall_bar = t0;
   return true;
}

//====================================================================
// 🟧 โซนซ้อน: หน้าต่างกว้าง InpZoneWidth_Pts ที่มีกำแพงต่างชนิด ≥ InpZoneMinTypes
//====================================================================
void DeleteObjs(string &names[]) {
   for(int i = 0; i < ArraySize(names); i++) ObjectDelete(0, names[i]);
   ArrayResize(names, 0);
}

void RememberObj(string &names[], string name) {
   int n = ArraySize(names);
   ArrayResize(names, n + 1, 64);
   names[n] = name;
}

color ZoneColor(int types) {
   if(types >= 5) return InpClrZone5;
   if(types == 4) return InpClrZone4;
   return InpClrZone3;
}

void DrawZones() {
   DeleteObjs(g_zone_objs);
   int n = ArraySize(g_walls);
   if(n == 0) return;

   // เรียงตามราคา (index)
   int idx[];
   ArrayResize(idx, n);
   for(int i = 0; i < n; i++) idx[i] = i;
   for(int i = 1; i < n; i++) {
      int key = idx[i], j = i - 1;
      while(j >= 0 && g_walls[idx[j]].px > g_walls[key].px) { idx[j + 1] = idx[j]; j--; }
      idx[j + 1] = key;
   }

   datetime now_t = CurrentZBarTime();
   long     per   = MathMax(60, PeriodSeconds(InpZ_Timeframe));
   datetime t_end = now_t + (datetime)(per * MathMax(1, InpZoneBarsRight));
   datetime t_min = now_t - (datetime)(InpW1_Days * DAY_SEC);
   double   width = PtsToPrice(InpZoneWidth_Pts);
   double   pad   = PtsToPrice(InpZonePad_Pts);
   int      zones = 0;

   // เส้นกำแพงเดี่ยว (เลือกได้)
   if(InpShowWallLines) {
      for(int i = 0; i < n; i++) {
         Wall w = g_walls[i];
         datetime t0 = (w.t > t_min) ? w.t : t_min;
         if(w.type == 2 || w.type == 5) t0 = now_t;   // ตัวเลขกลม / Z*: เฉพาะแท่งปัจจุบัน
         string nl = OBJ_PREFIX + "WL_" + IntegerToString(i);
         ObjectCreate(0, nl, OBJ_TREND, 0, t0, w.px, t_end, w.px);
         ObjectSetInteger(0, nl, OBJPROP_COLOR, g_wclr[w.type]);
         ObjectSetInteger(0, nl, OBJPROP_STYLE, STYLE_DOT);
         ObjectSetInteger(0, nl, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(0, nl, OBJPROP_BACK, true);
         ObjectSetInteger(0, nl, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, nl, OBJPROP_HIDDEN, true);
         ObjectSetString(0,  nl, OBJPROP_TOOLTIP, StringFormat("%s @ %s | แตะแล้วไม่ทะลุ %d แท่ง | กำแพงอื่นในระยะ %.0f จุด: %d",
                                                              WallName(w.type, w.sub), DoubleToString(w.px, _Digits),
                                                              w.touches, InpConf_Pts, w.conf));
         RememberObj(g_zone_objs, nl);
      }
   }
   if(!InpShowZones) return;

   int a = 0;
   while(a < n) {
      int b = a;
      while(b + 1 < n && g_walls[idx[b + 1]].px - g_walls[idx[a]].px <= width) b++;
      bool has[NW];
      ArrayInitialize(has, false);
      int types = 0;
      for(int k = a; k <= b; k++) if(!has[g_walls[idx[k]].type]) { has[g_walls[idx[k]].type] = true; types++; }
      if(types < InpZoneMinTypes) { a++; continue; }

      // โซน: แถบราคา lo-hi (+ ขยาย), เริ่มที่กำแพงเก่าสุดในโซน (ไม่เกินช่วง W1)
      double   lo = g_walls[idx[a]].px, hi = g_walls[idx[b]].px;
      datetime t0 = now_t;
      string   tip = "", tags = "";
      for(int q = 0; q < NW; q++) if(has[q]) tags += (tags == "" ? "" : " ") + "W" + IntegerToString(q + 1);
      for(int k = a; k <= b; k++) {
         Wall w = g_walls[idx[k]];
         datetime wt = (w.type == 2 || w.type == 5) ? now_t : ((w.t > t_min) ? w.t : t_min);
         if(wt < t0) t0 = wt;
         tip += StringFormat("\n• %s @ %s (แตะไม่ทะลุ %d)", WallName(w.type, w.sub), DoubleToString(w.px, _Digits), w.touches);
      }
      string head = StringFormat("🧱 โซนซ้อน %d ชนิด (%s) | %d กำแพง | %s - %s (กว้าง %.0f จุด)",
                                 types, tags, b - a + 1, DoubleToString(lo, _Digits), DoubleToString(hi, _Digits), PriceToPts(hi - lo));
      string nr = OBJ_PREFIX + "ZN_" + IntegerToString(zones);
      string nt = nr + "_T";
      ObjectCreate(0, nr, OBJ_RECTANGLE, 0, t0, hi + pad, t_end, lo - pad);
      ObjectSetInteger(0, nr, OBJPROP_COLOR, ZoneColor(types));
      ObjectSetInteger(0, nr, OBJPROP_FILL, true);
      ObjectSetInteger(0, nr, OBJPROP_BACK, true);
      ObjectSetInteger(0, nr, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nr, OBJPROP_HIDDEN, true);
      ObjectSetString(0,  nr, OBJPROP_TOOLTIP, head + tip);
      ObjectCreate(0, nt, OBJ_TEXT, 0, t_end, (hi + lo) / 2.0);
      ObjectSetString(0,  nt, OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(0, nt, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, nt, OBJPROP_COLOR, InpClrZoneText);
      ObjectSetInteger(0, nt, OBJPROP_ANCHOR, ANCHOR_LEFT);
      ObjectSetInteger(0, nt, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nt, OBJPROP_HIDDEN, true);
      ObjectSetString(0,  nt, OBJPROP_TEXT, StringFormat(" 🧱%d %s", types, tags));
      ObjectSetString(0,  nt, OBJPROP_TOOLTIP, head + tip);
      RememberObj(g_zone_objs, nr);
      RememberObj(g_zone_objs, nt);
      zones++;
      a = b + 1;
   }
}

//====================================================================
// 📊 VRVP: volume profile ของช่วงแท่งที่มองเห็น (แท่งนอนชิดขอบขวา)
//====================================================================
// TF ของข้อมูล volume: M1 ถ้าช่วงไม่เกิน 50,000 แท่ง ไม่งั้นขยับเป็น M5 / M15 / H1
ENUM_TIMEFRAMES VPTimeframe(datetime t_from, datetime t_to) {
   ENUM_TIMEFRAMES tfs[4] = {PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_H1};
   for(int i = 0; i < 4; i++)
      if((long)(t_to - t_from) / PeriodSeconds(tfs[i]) <= 50000) return tfs[i];
   return PERIOD_H4;
}

string VPChartSig() {
   return StringFormat("%d|%d|%d|%d|%.5f|%.5f", (int)ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR), (int)ChartGetInteger(0, CHART_VISIBLE_BARS),
                       (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS), (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0),
                       ChartGetDouble(0, CHART_PRICE_MAX, 0), ChartGetDouble(0, CHART_PRICE_MIN, 0));
}

void VPRect(int k, int x, int y, int w, int h, color clr, string tip) {
   string name = OBJ_PREFIX + "VP_" + IntegerToString(k);
   if(ObjectFind(0, name) < 0) {
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, MathMax(1, w));
   ObjectSetInteger(0, name, OBJPROP_YSIZE, MathMax(1, h));
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetString(0,  name, OBJPROP_TOOLTIP, tip);
}

void VPLine(string tag, datetime t0, datetime t1, double px, color clr, ENUM_LINE_STYLE st, string tip) {
   string name = OBJ_PREFIX + "VPL_" + tag;
   if(ObjectFind(0, name) < 0) {
      ObjectCreate(0, name, OBJ_TREND, 0, t0, px, t1, px);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
   ObjectMove(0, name, 0, t0, px);
   ObjectMove(0, name, 1, t1, px);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, st);
   ObjectSetString(0,  name, OBJPROP_TOOLTIP, tip);
}

// ลบแถว VRVP ตั้งแต่ index from ขึ้นไป (from = 0 → ลบทั้งหมดรวมเส้น POC / VAH / VAL)
void VPClear(int from) {
   for(int k = from; k < g_vp_rows; k++) ObjectDelete(0, OBJ_PREFIX + "VP_" + IntegerToString(k));
   if(from == 0) ObjectsDeleteAll(0, OBJ_PREFIX + "VPL_");
   g_vp_rows = MathMin(g_vp_rows, from);
}

void DrawVRVP(bool force) {
   if(!InpShowVRVP) return;
   string sig = VPChartSig();
   int    first = (int)ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR);
   int    vis   = (int)ChartGetInteger(0, CHART_VISIBLE_BARS);
   bool   live  = (first - vis + 1 <= 0);   // มองเห็นแท่งล่าสุด → อัปเดตตามเวลา
   if(!force && sig == g_vp_sig && !(live && GetTickCount() - g_vp_last_ms >= 2000)) return;
   g_vp_sig     = sig;
   g_vp_last_ms = GetTickCount();

   int bars = Bars(_Symbol, PERIOD_CURRENT);
   if(first < 0 || vis <= 0 || bars <= 0) { VPClear(0); return; }
   first = MathMin(first, bars - 1);
   int      last   = MathMax(0, first - vis + 1);
   datetime t_from = iTime(_Symbol, PERIOD_CURRENT, first);
   datetime t_last = iTime(_Symbol, PERIOD_CURRENT, last);
   datetime t_to   = t_last + (datetime)PeriodSeconds(PERIOD_CURRENT) - 1;
   if(t_from == 0 || t_last == 0) return;

   ENUM_TIMEFRAMES vtf = VPTimeframe(t_from, t_to);
   MqlRates r[];
   int got = CopyRates(_Symbol, vtf, t_from, t_to, r);
   if(got <= 0) { g_vp_sig = ""; VPClear(0); return; }   // ยังโหลดไม่ครบ → ลองใหม่รอบหน้า

   double lo = r[0].low, hi = r[0].high;
   for(int i = 1; i < got; i++) { lo = MathMin(lo, r[i].low); hi = MathMax(hi, r[i].high); }

   // ขนาดช่อง: 200 จุด หรือใหญ่ขึ้นจนแต่ละแถวสูงอย่างน้อย InpVP_MinRowPx พิกเซล
   int    ch    = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   int    cw    = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   double pmax  = ChartGetDouble(0, CHART_PRICE_MAX, 0), pmin = ChartGetDouble(0, CHART_PRICE_MIN, 0);
   double bin   = PtsToPrice(InpVP_Bin_Pts);
   if(bin <= 0.0 || ch <= 0 || cw <= 0 || pmax <= pmin) { VPClear(0); return; }
   int    mult  = 1;
   double px_per_price = ch / (pmax - pmin);
   while(bin * mult * px_per_price < MathMax(1, InpVP_MinRowPx) && mult < 1000) mult++;
   double step = bin * mult;
   double base = MathFloor(lo / step) * step;
   int    nb   = (int)MathFloor((hi - base) / step) + 1;
   if(nb <= 0 || nb > 20000) { VPClear(0); return; }

   double vol[];
   ArrayResize(vol, nb);
   ArrayInitialize(vol, 0.0);
   double total = 0.0;
   for(int i = 0; i < got; i++) {
      int a = (int)MathFloor((r[i].low - base) / step), z = (int)MathFloor((r[i].high - base) / step);
      a = MathMax(0, MathMin(nb - 1, a));
      z = MathMax(a, MathMin(nb - 1, z));
      double each = (double)r[i].tick_volume / (z - a + 1);
      for(int q = a; q <= z; q++) vol[q] += each;
      total += (double)r[i].tick_volume;
   }
   if(total <= 0.0) { VPClear(0); return; }

   // POC + Value Area: เริ่มที่ POC แล้วขยายไปฝั่งที่ volume มากกว่าทีละช่อง จนครบ InpVP_ValueAreaPct%
   int poc = 0;
   for(int q = 1; q < nb; q++) if(vol[q] > vol[poc]) poc = q;
   int    va_lo = poc, va_hi = poc;
   double acc   = vol[poc], need = total * MathMax(0.0, MathMin(100.0, InpVP_ValueAreaPct)) / 100.0;
   while(acc < need && (va_lo > 0 || va_hi < nb - 1)) {
      double up = (va_hi < nb - 1) ? vol[va_hi + 1] : -1.0;
      double dn = (va_lo > 0)      ? vol[va_lo - 1] : -1.0;
      if(up >= dn) { va_hi++; acc += up; }
      else         { va_lo--; acc += dn; }
   }

   // วาดแถว: แกน x ชิดขอบขวา, ความกว้างตามสัดส่วน volume ต่อ POC
   int    max_w = (int)(cw * MathMax(1.0, MathMin(100.0, InpVP_WidthPct)) / 100.0);
   int    k     = 0;
   string tf_s  = StringSubstr(EnumToString(vtf), 7);
   for(int q = 0; q < nb; q++) {
      if(vol[q] <= 0.0) continue;
      double p_lo = base + q * step, p_hi = p_lo + step;
      if(p_hi < pmin || p_lo > pmax) continue;
      int x0, y_top, x1, y_bot;
      if(!ChartTimePriceToXY(0, 0, t_last, p_hi, x0, y_top) || !ChartTimePriceToXY(0, 0, t_last, p_lo, x1, y_bot)) continue;
      y_top = MathMax(0, y_top);
      y_bot = MathMin(ch, y_bot);
      int h = MathMax(1, y_bot - y_top - (y_bot - y_top >= 4 ? 1 : 0));   // เว้นช่องว่าง 1 px เมื่อแถวสูงพอ
      int w = (int)MathRound(max_w * vol[q] / vol[poc]);
      if(w < 1) continue;
      color clr = (q == poc) ? InpClrVPPoc : ((q >= va_lo && q <= va_hi) ? InpClrVPValue : InpClrVP);
      VPRect(k++, cw - w, y_top, w, h, clr,
             StringFormat("VRVP %s - %s | volume %.0f (%.1f%%)%s | ข้อมูล %s, ช่อง %.0f จุด",
                          DoubleToString(p_lo, _Digits), DoubleToString(p_hi, _Digits), vol[q], 100.0 * vol[q] / total,
                          (q == poc ? " | POC" : ((q >= va_lo && q <= va_hi) ? " | Value Area" : "")), tf_s, PriceToPts(step)));
   }

   VPClear(k);   // ลบแถวที่เหลือจากรอบก่อน
   g_vp_rows = k;

   // เส้น POC / VAH / VAL ตลอดช่วงที่มองเห็น
   double poc_px = base + (poc + 0.5) * step;
   double vah    = base + (va_hi + 1) * step, val = base + va_lo * step;
   VPLine("POC", t_from, t_to, poc_px, InpClrVPPoc, STYLE_SOLID,
          StringFormat("POC %s (volume สูงสุดของช่วงที่มองเห็น)", DoubleToString(poc_px, _Digits)));
   VPLine("VAH", t_from, t_to, vah, InpClrVPEdge, STYLE_DOT,
          StringFormat("VAH %s (ขอบบน Value Area %.0f%%)", DoubleToString(vah, _Digits), InpVP_ValueAreaPct));
   VPLine("VAL", t_from, t_to, val, InpClrVPEdge, STYLE_DOT,
          StringFormat("VAL %s (ขอบล่าง Value Area %.0f%%)", DoubleToString(val, _Digits), InpVP_ValueAreaPct));
}

//====================================================================
// 🚀 EVENT HANDLERS
//====================================================================
int OnInit() {
   if(InpZ_Period < 3) { Print("❌ Period ต้องอย่างน้อย 3"); return(INIT_PARAMETERS_INCORRECT); }
   if(InpZoneWidth_Pts <= 0.0 || InpZoneMinTypes < 1 || InpZoneMinTypes > NW || InpVP_Bin_Pts <= 0.0) {
      Print("❌ ความกว้างโซน / จำนวนชนิดขั้นต่ำ (1-6) / ช่อง VRVP ไม่ถูกต้อง");
      return(INIT_PARAMETERS_INCORRECT);
   }
   g_pmult = (_Digits == 2 || _Digits == 4) ? 0.1 : 1.0;
   g_wclr[0] = InpClrW1; g_wclr[1] = InpClrW2; g_wclr[2] = InpClrW3;
   g_wclr[3] = InpClrW4; g_wclr[4] = InpClrW5; g_wclr[5] = InpClrW6;
   g_wall_bar = 0;
   g_vp_sig   = "";
   ArrayResize(g_walls, 0);
   ArrayResize(g_zone_objs, 0);
   g_vp_rows  = 0;
   ObjectsDeleteAll(0, OBJ_PREFIX);
   IndicatorSetString(INDICATOR_SHORTNAME, "7L Wall Zones + VRVP");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
   ObjectsDeleteAll(0, OBJ_PREFIX);
}

int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                const double &open[], const double &high[], const double &low[], const double &close[],
                const long &tick_volume[], const long &volume[], const int &spread[]) {
   bool changed = false;
   if(RebuildWalls()) { DrawZones(); changed = true; }
   DrawVRVP(prev_calculated == 0);
   if(changed) ChartRedraw(0);
   return(rates_total);
}

// เลื่อน / ซูม / ย่อขยายกราฟ → คำนวณ VRVP ใหม่ทันที
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
   if(id != CHARTEVENT_CHART_CHANGE) return;
   DrawVRVP(false);
   ChartRedraw(0);
}
//+------------------------------------------------------------------+
