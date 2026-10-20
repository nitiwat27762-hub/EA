//+------------------------------------------------------------------+
//|                                     Seven_Lines_Context_Ind.mq5  |
//|     Z หลายนิยาม: ระยะห่างราคากับเส้น ÷ ความเบี่ยงเบนปกติของเส้นนั้น |
//+------------------------------------------------------------------+
//
// 📐 นิยามเดียวกันทุกเส้น (v2.00)
//  Z = (ราคา − เส้นกลาง) ÷ ค่าเบี่ยงเบนปกติรอบเส้นนั้น
//  หน้าต่าง 20 แท่ง = แท่งปิด 19 แท่งก่อนหน้า + ราคาที่วัด (เหมือน Counter EA: High = ฝั่ง SELL / Low = ฝั่ง BUY)
//  |Z| สุดขั้ว = ราคาห่างเส้นผิดปกติ → ควรถูกดีดกลับหาเส้น
//   R  เส้นถดถอยเชิงเส้น         ÷ max(SD ส่วนเหลือ, พื้น)        (เหมือน EA, วาดเส้น + แถบ ± 2σ)
//   S  SMA20                     ÷ SD20                          (เหมือน EA, วาดเส้น + แถบ ± 2σ)
//   Q  เส้นถดถอยโค้ง (กำลังสอง)  ÷ max(SD ส่วนเหลือ, พื้น)
//   M  Median 20                 ÷ max(1.4826 × MAD, พื้น)
//   V  Speed: ราคาปิด 4 แท่งก่อน ÷ (SD ของการเปลี่ยนแปลงต่อแท่งของแท่งปิด × √4)
//   E  EMA20                     ÷ max(SD แบบถ่วงน้ำหนัก exponential, พื้น)
//   พื้น = InpSigmaFloorMult × SD ของการเปลี่ยนแปลงราคาต่อแท่งในหน้าต่าง (กันตัวหารเล็กผิดปกติ)
//
// 🏷️ ป้ายแนวนอน: แท่งที่ Z_reg หรือ Z_SMA ที่ High / Low เกิน ±2.00 → แสดง Z ทั้ง 6 แบบ
//    ป้ายที่อยู่ใกล้กันถูกเรียงเป็นชั้นตามความกว้างตัวอักษรจริงบนจอ → ไม่ซ้อนกัน (จัดใหม่เมื่อซูม / เลื่อนกราฟ)
// 📊 ตารางสถิติ (มุมล่างซ้าย): ทุกแท่งในประวัติที่ |Z| > 2.00 แยกตามนิยาม
//    → % ที่ราคากลับไปแตะเส้นภายใน 8 แท่ง + ระยะไปต่อสูงสุดเฉลี่ยใน 8 แท่ง (ใช้เทียบว่านิยามไหนดีดกลับจริง)
//
#property copyright   "Commander's Quant System"
#property version     "2.10"
#property description "Z หลายนิยาม (ถดถอย / SMA / ถดถอยโค้ง / Median / Speed / EMA) + ป้ายค่า Z + สถิติการดีดกลับ"
#property indicator_chart_window
#property indicator_buffers 17
#property indicator_plots   15

#property indicator_label1  "Q ถดถอยโค้ง"
#property indicator_type1   DRAW_LINE
#property indicator_width1  2
#property indicator_label2  "Q +σ"
#property indicator_type2   DRAW_LINE
#property indicator_style2  STYLE_DOT
#property indicator_label3  "Q −σ"
#property indicator_type3   DRAW_LINE
#property indicator_style3  STYLE_DOT
#property indicator_label4  "M Median"
#property indicator_type4   DRAW_LINE
#property indicator_width4  2
#property indicator_label5  "M +σ"
#property indicator_type5   DRAW_LINE
#property indicator_style5  STYLE_DOT
#property indicator_label6  "M −σ"
#property indicator_type6   DRAW_LINE
#property indicator_style6  STYLE_DOT
#property indicator_label7  "E EMA"
#property indicator_type7   DRAW_LINE
#property indicator_width7  2
#property indicator_label8  "E +σ"
#property indicator_type8   DRAW_LINE
#property indicator_style8  STYLE_DOT
#property indicator_label9  "E −σ"
#property indicator_type9   DRAW_LINE
#property indicator_style9  STYLE_DOT
#property indicator_label10 "R ถดถอย"
#property indicator_type10  DRAW_LINE
#property indicator_style10 STYLE_DOT
#property indicator_label11 "R +σ"
#property indicator_type11  DRAW_LINE
#property indicator_style11 STYLE_DASH
#property indicator_label12 "R −σ"
#property indicator_type12  DRAW_LINE
#property indicator_style12 STYLE_DASH
#property indicator_label13 "S SMA20"
#property indicator_type13  DRAW_LINE
#property indicator_style13 STYLE_DOT
#property indicator_label14 "S +σ"
#property indicator_type14  DRAW_LINE
#property indicator_style14 STYLE_DASHDOT
#property indicator_label15 "S −σ"
#property indicator_type15  DRAW_LINE
#property indicator_style15 STYLE_DASHDOT

//====================================================================
// 🎛️ INPUT PARAMETERS
//====================================================================
input group "=== Z (สูตรเดียวกับ Counter EA) ==="
input int    InpZ_Period          = 20;      // จำนวนแท่งของหน้าต่าง (ทุกนิยาม)
input double InpSigmaFloorMult    = 0.50;    // พื้นตัวหาร = ค่านี้ × SD ของการเปลี่ยนแปลงราคาต่อแท่ง
input int    InpSpeedBars         = 4;       // V: เทียบกับราคาปิดกี่แท่งก่อน

input group "=== เส้นบนกราฟ ==="
input bool   InpShowReg           = true;    // R: วาดเส้นถดถอย
input bool   InpShowRegBand       = true;    // R: วาดแถบ ± σ
input bool   InpShowSMA           = true;    // S: วาดเส้น SMA20
input bool   InpShowSMABand       = true;    // S: วาดแถบ ± σ
input bool   InpShowQuad          = true;    // Q: วาดเส้นถดถอยโค้ง
input bool   InpShowQuadBand      = false;   // Q: วาดแถบ ± σ
input bool   InpShowMedian        = true;    // M: วาดเส้น Median
input bool   InpShowMedianBand    = false;   // M: วาดแถบ ± σ
input bool   InpShowEMA           = true;    // E: วาดเส้น EMA
input bool   InpShowEMABand       = false;   // E: วาดแถบ ± σ
input double InpBandZ             = 2.00;    // แถบ = เส้น ± ค่านี้ × σ

input group "=== ป้ายค่า Z (แนวนอน) ==="
input bool   InpShowLabels        = true;    // แสดงป้าย
input double InpLabelZ            = 2.00;    // ขึ้นป้ายเมื่อ Z_reg หรือ Z_SMA เกิน ±ค่านี้
input int    InpLabelBars         = 0;       // ย้อนหลังกี่แท่ง (0 = ทั้งหมด)
input int    InpLabelFontSize     = 7;       // ขนาดตัวอักษร
input int    InpLabelOffset_Px    = 6;       // ระยะห่างจากไส้เทียน (พิกเซล)

input group "=== ตารางสถิติ ==="
input bool   InpShowStats         = true;    // แสดงตารางสถิติการดีดกลับ (มุมล่างซ้าย)
input double InpStatZ             = 2.00;    // นับแท่งที่ |Z| เกินค่านี้
input int    InpStatBars          = 8;       // ราคาต้องกลับแตะเส้นภายในกี่แท่ง

input group "=== สี ==="
input color  InpClrReg            = clrGold;           // R
input color  InpClrSMA            = clrDarkKhaki;      // S
input color  InpClrQuad           = clrMediumOrchid;   // Q
input color  InpClrMedian         = clrTurquoise;      // M
input color  InpClrEMA            = clrGoldenrod;      // E
input color  InpClrLabelSell      = clrOrangeRed;      // ป้ายฝั่ง SELL (เหนือแท่ง)
input color  InpClrLabelBuy       = clrDeepSkyBlue;    // ป้ายฝั่ง BUY (ใต้แท่ง)
input color  InpClrStats          = clrSilver;         // ตารางสถิติ

//====================================================================
// 🔒 INTERNAL
//====================================================================
#define ZN 6
const string PFX         = "7LCTX_";
const string Z_TAG[ZN]   = {"R", "S", "Q", "M", "V", "E"};
const string Z_NAME[ZN]  = {"ถดถอย", "SMA20", "ถดถอยโค้ง", "Median", "Speed", "EMA20"};

struct ZSet {
   double z[ZN];
   double ctr[ZN];   // ราคาเส้นกลาง (V = ราคาปิด InpSpeedBars แท่งก่อน)
   double sig[ZN];   // ตัวหาร (ราคา)
};

double bQ[], bQp[], bQm[], bM[], bMp[], bMm[], bE[], bEp[], bEm[];
double bR[], bRp[], bRm[], bS[], bSp[], bSm[];
double cEma[], cEVar[];

double g_pmult = 1.0;
double g_w[], g_t[];             // หน้าต่างราคา / ที่เรียงลำดับ (ใช้ซ้ำ ไม่ต้องจองใหม่ทุกครั้ง)
double g_su2 = 0.0, g_su4 = 0.0; // Σu², Σu⁴ ของ u = x − (n−1)/2 (ถดถอยโค้ง)
int    g_warm  = 0;
int    g_rates = 0;
double g_hi[], g_lo[];           // สำเนา High / Low สำหรับจัดชั้นป้าย

// ป้าย (เรียงตาม index แท่งจากเก่า→ใหม่)
int    g_lb_idx[];
int    g_lb_side[];              // 0 = SELL (High), 1 = BUY (Low)
string g_lb_name[];
double g_lb_w[];                 // ความกว้างตัวอักษร (พิกเซล)
bool   g_lb_dirty = false;
double g_last_hi = 0.0, g_last_lo = 0.0;   // High / Low ของแท่งปัจจุบันตอนจัดชั้นล่าสุด
long   g_ly_scale = -1, g_ly_first = -1, g_ly_width = -1, g_ly_h = -1;
double g_ly_pmin = 0.0, g_ly_pmax = 0.0;

// สถิติ
int    g_st_next = 0;            // แท่งถัดไปที่จะนับ (ต้องมีครบ InpStatBars แท่งหลังจากนั้น)
int    g_st_bars = 0;
int    g_st_n[ZN], g_st_touch[ZN];
double g_st_adv[ZN];

//====================================================================
// 🧰 HELPERS
//====================================================================
double PriceToPts(double px) { return px / (g_pmult * _Point); }
string Sgn(double v, int digits) { return (v >= 0.0 ? "+" : "") + DoubleToString(v, digits); }

double Median(double &a[], int n) {
   ArraySort(a);
   return (n % 2 == 1) ? a[n / 2] : 0.5 * (a[n / 2 - 1] + a[n / 2]);
}

// Z ทั้ง 6 แบบของแท่ง i ที่ราคา P (แท่งปิด i−n+1 .. i−1 + P)
bool ZAll(const double &close[], int i, double P, ZSet &s) {
   int n = InpZ_Period, k = InpSpeedBars;
   if(i < n + k) return false;
   for(int q = 0; q < n - 1; q++) g_w[q] = close[i - n + 1 + q];
   g_w[n - 1] = P;
   double ref = close[i - 1];

   // พื้นตัวหาร: SD ของส่วนต่างต่อแท่งในหน้าต่าง (รวม P)
   double sd = 0.0, sdd = 0.0;
   for(int q = 1; q < n; q++) { double d = g_w[q] - g_w[q - 1]; sd += d; sdd += d * d; }
   double nd = n - 1.0, md = sd / nd, vd = sdd / nd - md * md;
   double flo = (vd > 0.0) ? MathSqrt(vd) * InpSigmaFloorMult : 0.0;

   double nn = (double)n, uc = (nn - 1.0) / 2.0;
   double sy = 0.0, syy = 0.0, sxy = 0.0, suy = 0.0, su2y = 0.0;
   for(int q = 0; q < n; q++) {
      double y = g_w[q] - ref, u = q - uc;
      sy += y; syy += y * y; sxy += q * y; suy += u * y; su2y += u * u * y;
   }
   double yP = P - ref;

   // R: เส้นถดถอยเชิงเส้น
   double sx  = nn * (nn - 1.0) / 2.0;
   double sxx = (nn - 1.0) * nn * (2.0 * nn - 1.0) / 6.0;
   double b   = (nn * sxy - sx * sy) / (nn * sxx - sx * sx);
   double a   = (sy - b * sx) / nn;
   double fr  = a + b * (nn - 1.0);
   double ssr = syy - a * sy - b * sxy;
   s.ctr[0] = ref + fr;
   s.sig[0] = MathMax(MathSqrt(MathMax(ssr, 0.0) / nn), flo);

   // S: SMA20
   double mean = sy / nn, vs = syy / nn - mean * mean;
   if(vs <= 0.0) return false;
   s.ctr[1] = ref + mean;
   s.sig[1] = MathSqrt(vs);

   // Q: ถดถอยกำลังสอง (u กึ่งกลาง → สมการปกติแยกได้)
   double det = nn * g_su4 - g_su2 * g_su2;
   double aq  = (sy * g_su4 - g_su2 * su2y) / det;
   double bq  = suy / g_su2;
   double cq  = (nn * su2y - g_su2 * sy) / det;
   double ssq = 0.0;
   for(int q = 0; q < n; q++) {
      double u = q - uc, e = (g_w[q] - ref) - (aq + bq * u + cq * u * u);
      ssq += e * e;
   }
   s.ctr[2] = ref + aq + bq * uc + cq * uc * uc;
   s.sig[2] = MathMax(MathSqrt(ssq / nn), flo);

   // M: Median + MAD
   for(int q = 0; q < n; q++) g_t[q] = g_w[q];
   double med = Median(g_t, n);
   for(int q = 0; q < n; q++) g_t[q] = MathAbs(g_w[q] - med);
   s.ctr[3] = med;
   s.sig[3] = MathMax(1.4826 * Median(g_t, n), flo);

   // V: Speed (เทียบราคาปิด k แท่งก่อน, ตัวหารจากส่วนต่างของแท่งปิดเท่านั้น)
   double vsum = 0.0, vss = 0.0;
   for(int j = i - n + 1; j <= i - 1; j++) { double d = close[j] - close[j - 1]; vsum += d; vss += d * d; }
   double vm = vsum / nd, vv = vss / nd - vm * vm;
   s.ctr[4] = close[i - k];
   s.sig[4] = (vv > 0.0) ? MathSqrt(vv) * MathSqrt((double)k) : 0.0;

   // E: EMA + ความแปรปรวนแบบ exponential (ต่อจากค่าของแท่งก่อนหน้า)
   double al = 2.0 / (nn + 1.0), ep = cEma[i - 1], vp = cEVar[i - 1];
   s.ctr[5] = al * P + (1.0 - al) * ep;
   s.sig[5] = MathMax(MathSqrt(MathMax((1.0 - al) * (vp + al * (P - ep) * (P - ep)), 0.0)), flo);

   for(int t = 0; t < ZN; t++) s.z[t] = (s.sig[t] > 0.0) ? (P - s.ctr[t]) / s.sig[t] : 0.0;
   return true;
}

//====================================================================
// 🏷️ ป้ายแนวนอน + จัดชั้นไม่ให้ซ้อนกัน
//====================================================================
int LabelFind(int idx, int side) {
   for(int k = ArraySize(g_lb_idx) - 1; k >= 0 && g_lb_idx[k] >= idx; k--)
      if(g_lb_idx[k] == idx && g_lb_side[k] == side) return k;
   return -1;
}

void LabelRemove(int k) {
   ObjectDelete(0, g_lb_name[k]);
   int n = ArraySize(g_lb_idx);
   for(int q = k; q < n - 1; q++) {
      g_lb_idx[q] = g_lb_idx[q + 1]; g_lb_side[q] = g_lb_side[q + 1];
      g_lb_name[q] = g_lb_name[q + 1]; g_lb_w[q] = g_lb_w[q + 1];
   }
   ArrayResize(g_lb_idx, n - 1); ArrayResize(g_lb_side, n - 1);
   ArrayResize(g_lb_name, n - 1); ArrayResize(g_lb_w, n - 1);
   g_lb_dirty = true;
}

void LabelsClear() {
   ObjectsDeleteAll(0, PFX + "L");
   ArrayResize(g_lb_idx, 0); ArrayResize(g_lb_side, 0);
   ArrayResize(g_lb_name, 0); ArrayResize(g_lb_w, 0);
   g_lb_dirty = true;
}

void UpdateLabel(int i, const datetime &time[], const double &high[], const double &low[], const double &close[]) {
   for(int side = 0; side < 2; side++) {
      double P = (side == 0) ? high[i] : low[i];
      ZSet   s;
      bool   hit = ZAll(close, i, P, s) &&
                   ((side == 0) ? (s.z[0] > InpLabelZ || s.z[1] > InpLabelZ) : (s.z[0] < -InpLabelZ || s.z[1] < -InpLabelZ));
      int    k   = LabelFind(i, side);
      if(!hit) { if(k >= 0) LabelRemove(k); continue; }

      string txt = StringFormat("R%s S%s | Q%s M%s V%s E%s", Sgn(s.z[0], 2), Sgn(s.z[1], 2),
                                Sgn(s.z[2], 2), Sgn(s.z[3], 2), Sgn(s.z[4], 2), Sgn(s.z[5], 2));
      string tip = StringFormat("%s %s @ %s", (side == 0 ? "High" : "Low"), TimeToString(time[i], TIME_DATE|TIME_MINUTES),
                                DoubleToString(P, _Digits));
      for(int t = 0; t < ZN; t++)
         tip += StringFormat("\n%s %s: Z %s | เส้น %s | σ %.0f จุด", Z_TAG[t], Z_NAME[t], Sgn(s.z[t], 2),
                             DoubleToString(s.ctr[t], _Digits), PriceToPts(s.sig[t]));
      string name = PFX + (side == 0 ? "LS_" : "LB_") + IntegerToString((long)time[i]);
      if(ObjectFind(0, name) < 0) {
         ObjectCreate(0, name, OBJ_TEXT, 0, time[i], P);
         ObjectSetString(0,  name, OBJPROP_FONT, "Arial");
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpLabelFontSize);
         ObjectSetInteger(0, name, OBJPROP_ANCHOR, (side == 0) ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER);
         ObjectSetInteger(0, name, OBJPROP_COLOR, (side == 0) ? InpClrLabelSell : InpClrLabelBuy);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      }
      ObjectSetString(0, name, OBJPROP_TEXT, txt);
      ObjectSetString(0, name, OBJPROP_TOOLTIP, tip);

      uint tw = 0, th = 0;
      TextSetFont("Arial", -InpLabelFontSize * 10);
      TextGetSize(txt, tw, th);
      if(k < 0) {
         k = ArraySize(g_lb_idx);
         ArrayResize(g_lb_idx, k + 1); ArrayResize(g_lb_side, k + 1);
         ArrayResize(g_lb_name, k + 1); ArrayResize(g_lb_w, k + 1);
         g_lb_idx[k] = i; g_lb_side[k] = side; g_lb_name[k] = name; g_lb_w[k] = 0.0;
         g_lb_dirty = true;
      }
      double w = (double)tw + 8.0;
      if(MathAbs(w - g_lb_w[k]) > 0.5) { g_lb_w[k] = w; g_lb_dirty = true; }
   }
}

// จัดชั้นป้ายในกลุ่ม: ป้ายที่ช่วงแนวนอนทับกันได้ชั้นต่างกัน, ทั้งกลุ่มใช้ฐานเดียวกัน (High สูงสุด / Low ต่ำสุดของแท่งที่ป้ายพาดผ่าน)
void PlaceCluster(const int &cl[], int cn, int side, double bar_px, double ppx, double row_px) {
   double row_end[];
   int    rows[];
   int    nr = 0;
   double cend = 0.0;
   ArrayResize(rows, cn);
   for(int q = 0; q < cn; q++) {
      double x0 = g_lb_idx[cl[q]] * bar_px, x1 = x0 + g_lb_w[cl[q]];
      int    r  = 0;
      while(r < nr && row_end[r] >= x0) r++;
      if(r == nr) { nr++; ArrayResize(row_end, nr); }
      row_end[r] = x1;
      rows[q]    = r;
      cend       = MathMax(cend, x1);
   }
   int    i0   = g_lb_idx[cl[0]];
   int    i1   = MathMin(g_rates - 1, (int)MathCeil(cend / bar_px));
   double base = (side == 0) ? g_hi[i0] : g_lo[i0];
   for(int j = i0 + 1; j <= i1; j++) base = (side == 0) ? MathMax(base, g_hi[j]) : MathMin(base, g_lo[j]);
   for(int q = 0; q < cn; q++) {
      double off = (InpLabelOffset_Px + rows[q] * row_px) * ppx;
      double y   = (side == 0) ? base + off : base - off;
      if(MathAbs(ObjectGetDouble(0, g_lb_name[cl[q]], OBJPROP_PRICE) - y) > _Point)
         ObjectSetDouble(0, g_lb_name[cl[q]], OBJPROP_PRICE, y);
   }
}

// จัดชั้นเฉพาะป้ายในช่วงที่มองเห็น (+ ป้ายทางซ้ายที่ข้อความยาวเข้ามาในจอ) เมื่อป้าย / ซูม / เลื่อน / สเกลราคาเปลี่ยน
void LayoutLabels() {
   long   scale = ChartGetInteger(0, CHART_SCALE);
   long   first = ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR);
   long   wb    = ChartGetInteger(0, CHART_WIDTH_IN_BARS);
   long   hpx   = ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   double pmax  = ChartGetDouble(0, CHART_PRICE_MAX);
   double pmin  = ChartGetDouble(0, CHART_PRICE_MIN);
   if(!g_lb_dirty && scale == g_ly_scale && first == g_ly_first && wb == g_ly_width && hpx == g_ly_h &&
      pmax == g_ly_pmax && pmin == g_ly_pmin) return;
   g_ly_scale = scale; g_ly_first = first; g_ly_width = wb; g_ly_h = hpx; g_ly_pmax = pmax; g_ly_pmin = pmin;
   g_lb_dirty = false;

   int nl = ArraySize(g_lb_idx);
   if(nl == 0 || hpx <= 0 || pmax <= pmin || g_rates <= 0) return;
   double bar_px = MathPow(2.0, (double)scale);
   double ppx    = (pmax - pmin) / (double)hpx;
   uint   tw = 0, th = 0;
   TextSetFont("Arial", -InpLabelFontSize * 10);
   TextGetSize("Rg+0.", tw, th);
   double row_px = (double)th + 2.0;
   double maxw   = 0.0;
   for(int k = 0; k < nl; k++) maxw = MathMax(maxw, g_lb_w[k]);
   int vis_lo = g_rates - 1 - (int)first;
   int vis_hi = vis_lo + (int)wb + 1;
   int lo_idx = vis_lo - (int)(maxw / bar_px) - 2;

   int cl[];
   for(int side = 0; side < 2; side++) {
      int    cn   = 0;
      double cend = 0.0;
      for(int k = 0; k < nl; k++) {
         if(g_lb_side[k] != side || g_lb_idx[k] < lo_idx || g_lb_idx[k] > vis_hi) continue;
         double x0 = g_lb_idx[k] * bar_px, x1 = x0 + g_lb_w[k];
         if(cn > 0 && x0 > cend) { PlaceCluster(cl, cn, side, bar_px, ppx, row_px); cn = 0; }
         ArrayResize(cl, cn + 1);
         cl[cn++] = k;
         cend = (cn == 1) ? x1 : MathMax(cend, x1);
      }
      if(cn > 0) PlaceCluster(cl, cn, side, bar_px, ppx, row_px);
   }
}

//====================================================================
// 📊 สถิติการดีดกลับ
//====================================================================
void StatsReset() {
   g_st_next = g_warm;
   g_st_bars = 0;
   ArrayInitialize(g_st_n, 0);
   ArrayInitialize(g_st_touch, 0);
   ArrayInitialize(g_st_adv, 0.0);
}

// แท่ง j (ปิดแล้ว + มีแท่งถัดไปครบ InpStatBars): Z ที่ High / Low เกินเกณฑ์ → กลับแตะเส้นไหม (รวมราคาปิดของแท่ง j เอง)
void StatBar(int j, const double &high[], const double &low[], const double &close[]) {
   double fmin = low[j + 1], fmax = high[j + 1];
   for(int q = 2; q <= InpStatBars; q++) { fmin = MathMin(fmin, low[j + q]); fmax = MathMax(fmax, high[j + q]); }
   ZSet sh, sl;
   if(ZAll(close, j, high[j], sh))
      for(int t = 0; t < ZN; t++) {
         if(sh.z[t] <= InpStatZ) continue;
         g_st_n[t]++;
         if(close[j] <= sh.ctr[t] || fmin <= sh.ctr[t]) g_st_touch[t]++;
         g_st_adv[t] += PriceToPts(MathMax(0.0, fmax - high[j]));
      }
   if(ZAll(close, j, low[j], sl))
      for(int t = 0; t < ZN; t++) {
         if(sl.z[t] >= -InpStatZ) continue;
         g_st_n[t]++;
         if(close[j] >= sl.ctr[t] || fmax >= sl.ctr[t]) g_st_touch[t]++;
         g_st_adv[t] += PriceToPts(MathMax(0.0, low[j] - fmin));
      }
   g_st_bars++;
}

void StatLine(int row, string text) {
   string nm = PFX + "ST_" + IntegerToString(row);
   if(ObjectFind(0, nm) < 0) {
      ObjectCreate(0, nm, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_LOWER);
      ObjectSetInteger(0, nm, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
      ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, 8);
      ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, 18 + row * 15);
      ObjectSetString(0,  nm, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, nm, OBJPROP_COLOR, InpClrStats);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
   }
   ObjectSetString(0, nm, OBJPROP_TEXT, text);
}

void DrawStats() {
   if(!InpShowStats) return;
   for(int t = ZN - 1; t >= 0; t--) {
      double pct = (g_st_n[t] > 0) ? 100.0 * g_st_touch[t] / g_st_n[t] : 0.0;
      double adv = (g_st_n[t] > 0) ? g_st_adv[t] / g_st_n[t] : 0.0;
      StatLine(ZN - 1 - t, StringFormat("%s %-9s %7d ครั้ง | แตะเส้น %5.1f%% | ไปต่อสูงสุดเฉลี่ย %6.0f จุด",
                                         Z_TAG[t], Z_NAME[t], g_st_n[t], pct, adv));
   }
   StatLine(ZN, StringFormat("📊 |Z| > %.2f ที่ High / Low → กลับแตะเส้นภายใน %d แท่ง (นับแล้ว %d แท่ง, V = กลับถึงราคาปิด %d แท่งก่อน)",
                             InpStatZ, InpStatBars, g_st_bars, InpSpeedBars));
}

//====================================================================
// 🚀 EVENT HANDLERS
//====================================================================
void SetPlot(int plot, bool show, color clr) {
   if(!show) PlotIndexSetInteger(plot, PLOT_DRAW_TYPE, DRAW_NONE);
   PlotIndexSetInteger(plot, PLOT_LINE_COLOR, clr);
   PlotIndexSetInteger(plot, PLOT_DRAW_BEGIN, g_warm);
   PlotIndexSetDouble(plot, PLOT_EMPTY_VALUE, EMPTY_VALUE);
}

int OnInit() {
   if(InpZ_Period < 5 || InpSpeedBars < 1 || InpSigmaFloorMult < 0.0 || InpBandZ <= 0.0 || InpLabelZ <= 0.0 ||
      InpLabelBars < 0 || InpLabelFontSize < 4 || InpStatZ <= 0.0 || InpStatBars < 1) {
      Print("❌ ค่า Input ไม่ถูกต้อง (หน้าต่าง ≥ 5, Speed ≥ 1 แท่ง, เกณฑ์ > 0, แท่งสถิติ ≥ 1)");
      return(INIT_PARAMETERS_INCORRECT);
   }
   g_pmult = (_Digits == 2 || _Digits == 4) ? 0.1 : 1.0;
   int n = InpZ_Period;
   ArrayResize(g_w, n);
   ArrayResize(g_t, n);
   double uc = (n - 1.0) / 2.0;
   g_su2 = 0.0; g_su4 = 0.0;
   for(int q = 0; q < n; q++) { double u = q - uc; g_su2 += u * u; g_su4 += u * u * u * u; }
   g_warm = MathMax(3 * n, n + InpSpeedBars + 2);

   SetIndexBuffer(0,  bQ,    INDICATOR_DATA);
   SetIndexBuffer(1,  bQp,   INDICATOR_DATA);
   SetIndexBuffer(2,  bQm,   INDICATOR_DATA);
   SetIndexBuffer(3,  bM,    INDICATOR_DATA);
   SetIndexBuffer(4,  bMp,   INDICATOR_DATA);
   SetIndexBuffer(5,  bMm,   INDICATOR_DATA);
   SetIndexBuffer(6,  bE,    INDICATOR_DATA);
   SetIndexBuffer(7,  bEp,   INDICATOR_DATA);
   SetIndexBuffer(8,  bEm,   INDICATOR_DATA);
   SetIndexBuffer(9,  bR,    INDICATOR_DATA);
   SetIndexBuffer(10, bRp,   INDICATOR_DATA);
   SetIndexBuffer(11, bRm,   INDICATOR_DATA);
   SetIndexBuffer(12, bS,    INDICATOR_DATA);
   SetIndexBuffer(13, bSp,   INDICATOR_DATA);
   SetIndexBuffer(14, bSm,   INDICATOR_DATA);
   SetIndexBuffer(15, cEma,  INDICATOR_CALCULATIONS);
   SetIndexBuffer(16, cEVar, INDICATOR_CALCULATIONS);
   SetPlot(0, InpShowQuad,       InpClrQuad);
   SetPlot(1, InpShowQuadBand,   InpClrQuad);
   SetPlot(2, InpShowQuadBand,   InpClrQuad);
   SetPlot(3, InpShowMedian,     InpClrMedian);
   SetPlot(4, InpShowMedianBand, InpClrMedian);
   SetPlot(5, InpShowMedianBand, InpClrMedian);
   SetPlot(6, InpShowEMA,        InpClrEMA);
   SetPlot(7, InpShowEMABand,    InpClrEMA);
   SetPlot(8, InpShowEMABand,    InpClrEMA);
   SetPlot(9,  InpShowReg,       InpClrReg);
   SetPlot(10, InpShowRegBand,   InpClrReg);
   SetPlot(11, InpShowRegBand,   InpClrReg);
   SetPlot(12, InpShowSMA,       InpClrSMA);
   SetPlot(13, InpShowSMABand,   InpClrSMA);
   SetPlot(14, InpShowSMABand,   InpClrSMA);

   IndicatorSetString(INDICATOR_SHORTNAME, "7L Z หลายนิยาม");
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
   ObjectsDeleteAll(0, PFX);
   ArrayResize(g_lb_idx, 0); ArrayResize(g_lb_side, 0); ArrayResize(g_lb_name, 0); ArrayResize(g_lb_w, 0);
   g_ly_scale = -1;
   StatsReset();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
   ObjectsDeleteAll(0, PFX);
}

int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[], const double &high[], const double &low[],
                const double &close[], const long &tick_volume[], const long &volume[], const int &spread[]) {
   if(rates_total < g_warm + InpStatBars + 5) return(0);
   int start = (prev_calculated > 0) ? prev_calculated - 1 : 0;
   if(start == 0) { LabelsClear(); StatsReset(); }

   g_rates = rates_total;
   ArrayResize(g_hi, rates_total);
   ArrayResize(g_lo, rates_total);
   ArrayCopy(g_hi, high, start, start, rates_total - start);
   ArrayCopy(g_lo, low,  start, start, rates_total - start);

   double al = 2.0 / (InpZ_Period + 1.0);
   for(int i = start; i < rates_total; i++) {
      // EMA + ความแปรปรวนแบบ exponential ของราคาปิด
      if(i == 0) { cEma[i] = close[i]; cEVar[i] = 0.0; }
      else {
         double d = close[i] - cEma[i - 1];
         cEma[i]  = cEma[i - 1] + al * d;
         cEVar[i] = (1.0 - al) * (cEVar[i - 1] + al * d * d);
      }
      // เส้นกลาง ± แถบ ณ ราคาปิด (R / S / Q / M / E)
      bR[i] = EMPTY_VALUE; bRp[i] = EMPTY_VALUE; bRm[i] = EMPTY_VALUE;
      bS[i] = EMPTY_VALUE; bSp[i] = EMPTY_VALUE; bSm[i] = EMPTY_VALUE;
      bQ[i] = EMPTY_VALUE; bQp[i] = EMPTY_VALUE; bQm[i] = EMPTY_VALUE;
      bM[i] = EMPTY_VALUE; bMp[i] = EMPTY_VALUE; bMm[i] = EMPTY_VALUE;
      bE[i] = EMPTY_VALUE; bEp[i] = EMPTY_VALUE; bEm[i] = EMPTY_VALUE;
      ZSet s;
      if(i < g_warm || !ZAll(close, i, close[i], s)) continue;
      bR[i] = s.ctr[0]; bRp[i] = s.ctr[0] + InpBandZ * s.sig[0]; bRm[i] = s.ctr[0] - InpBandZ * s.sig[0];
      bS[i] = s.ctr[1]; bSp[i] = s.ctr[1] + InpBandZ * s.sig[1]; bSm[i] = s.ctr[1] - InpBandZ * s.sig[1];
      bQ[i] = s.ctr[2]; bQp[i] = s.ctr[2] + InpBandZ * s.sig[2]; bQm[i] = s.ctr[2] - InpBandZ * s.sig[2];
      bM[i] = s.ctr[3]; bMp[i] = s.ctr[3] + InpBandZ * s.sig[3]; bMm[i] = s.ctr[3] - InpBandZ * s.sig[3];
      bE[i] = s.ctr[5]; bEp[i] = s.ctr[5] + InpBandZ * s.sig[5]; bEm[i] = s.ctr[5] - InpBandZ * s.sig[5];
   }

   // 🏷️ ป้าย (แท่งปัจจุบันประเมินใหม่ทุก Tick)
   if(InpShowLabels) {
      int from = (InpLabelBars > 0) ? MathMax(g_warm, rates_total - InpLabelBars) : g_warm;
      for(int i = MathMax(start, from); i < rates_total; i++) UpdateLabel(i, time, high, low, close);
      int last = rates_total - 1;   // แท่งปัจจุบันทำ High / Low ใหม่ → ฐานของป้ายเปลี่ยน
      if(high[last] != g_last_hi || low[last] != g_last_lo) {
         g_last_hi = high[last];
         g_last_lo = low[last];
         if(LabelFind(last, 0) >= 0 || LabelFind(last, 1) >= 0) g_lb_dirty = true;
      }
      LayoutLabels();
   }

   // 📊 สถิติ: นับเฉพาะแท่งที่มีแท่งถัดไปปิดครบ InpStatBars แท่งแล้ว (แต่ละแท่งนับครั้งเดียว)
   if(InpShowStats) {
      bool changed = (start == 0);
      while(g_st_next + InpStatBars <= rates_total - 2) {
         StatBar(g_st_next, high, low, close);
         g_st_next++;
         changed = true;
      }
      if(changed) DrawStats();
   }
   return(rates_total);
}

// ซูม / เลื่อน / ย่อขยายกราฟ → จัดชั้นป้ายใหม่
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
   if(id != CHARTEVENT_CHART_CHANGE || !InpShowLabels) return;
   LayoutLabels();
   ChartRedraw(0);
}
//+------------------------------------------------------------------+
