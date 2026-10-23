//+------------------------------------------------------------------+
//|                                     Seven_Lines_Context_Ind.mq5  |
//|        Z_reg / Z_SMA แบบเดียวกับ Counter EA + เกณฑ์ปรับตามตลาด      |
//+------------------------------------------------------------------+
//
// 📐 Z (สูตรเดียวกับ Counter EA, หน้าต่าง 20 แท่ง = แท่งปิด 19 แท่งก่อนหน้า + ราคาที่วัด)
//  • Z_reg = (ราคา − เส้นถดถอย) ÷ max(SD ส่วนเหลือ, 0.5 × SD ของส่วนต่างต่อแท่ง)
//  • Z_SMA = (ราคา − SMA20) ÷ SD20
//  • โหมดตัวหาร σ (InpSigmaMode):
//     CLOSE = SD จากราคาปิด (เหมือน EA)
//     RANGE = σ จากช่วงแท่ง (Parkinson: √(Σ(High−Low)² ÷ (4·ln2·n)) ของ 19 แท่งก่อน) × ตัวปรับสเกล
//             ตัวปรับสเกล = ค่าเฉลี่ยถ่วง (EMA) ของ σ_ราคาปิด ÷ σ_ช่วงแท่ง ย้อนหลัง → ค่าเฉลี่ยระยะยาวเท่า CLOSE
//             แต่ช่วงที่ไส้ยาวขึ้น (ราคาปิดไม่ค่อยหนี) ตัวหารโตตาม → Z ไม่พองเกินจริง
//
// 🎚️ เกณฑ์ (InpThrMode)
//  • FIXED = T2 / T3 / T4 = 2.5 / 3.0 / 3.5 (เหมือน EA)
//  • PCT   = เกณฑ์ปรับตามตลาด: ค่า Z ที่ top 1% / 0.3% / 0.1% ของแท่งย้อนหลัง 20 วัน (ไม่รวมแท่งปัจจุบัน)
//            วัดจาก Z สุดขั้วของแต่ละแท่ง = max(Z_reg, Z_SMA ที่ High, −Z_reg, −Z_SMA ที่ Low)
//
// 🖼️ แสดงผลแบบเดียวกับ Counter EA
//  • ป้าย "R+2.31 | S+2.05" บนแท่งที่ Z ที่ High (SELL) / Low (BUY) เกินเกณฑ์ T2 (สี = เข้าระดับ, เทา = ไม่ครบ)
//  • ป้าย Z_float "F+1.23" = (ราคาเปิด − SMA ตอนเปิดแท่ง) ÷ SD (แท่งปัจจุบันแสดงเสมอ)
//  • เส้นแนวนอนระดับ Z (เส้นถดถอย / SMA20 ± เกณฑ์ T2) + ป้าย Z สดที่ขอบขวา
// 📅 ตารางอัตราการเกิดรายเดือน (มุมขวาล่าง): % ของแท่งที่ Z เกิน 2.0 / 2.5 / 3.0 + ค่า Z ที่ top 1% / 0.3% / 0.1%
//    ใช้ดูว่าความถี่ของ Z สุดโต่งเพิ่มขึ้นตามปีจริงไหม และโหมด RANGE / PCT ช่วยให้คงที่ได้ไหม
//
#property copyright   "Commander's Quant System"
#property version     "3.00"
#property description "Z_reg / Z_SMA แบบเดียวกับ Counter EA + เกณฑ์ปรับตามตลาด (เปอร์เซ็นไทล์) + σ จากช่วงแท่ง + อัตราการเกิดรายเดือน"
#property indicator_chart_window
#property indicator_buffers 11
#property indicator_plots   6

#property indicator_label1  "R เส้นถดถอย"
#property indicator_type1   DRAW_LINE
#property indicator_style1  STYLE_DOT
#property indicator_label2  "R +T2"
#property indicator_type2   DRAW_LINE
#property indicator_style2  STYLE_DASH
#property indicator_label3  "R −T2"
#property indicator_type3   DRAW_LINE
#property indicator_style3  STYLE_DASH
#property indicator_label4  "S SMA20"
#property indicator_type4   DRAW_LINE
#property indicator_style4  STYLE_DOT
#property indicator_label5  "S +T2"
#property indicator_type5   DRAW_LINE
#property indicator_style5  STYLE_DASHDOT
#property indicator_label6  "S −T2"
#property indicator_type6   DRAW_LINE
#property indicator_style6  STYLE_DASHDOT

enum ENUM_SIGMA_MODE {
   SIG_CLOSE = 0,   // SD จากราคาปิด (เหมือน EA)
   SIG_RANGE = 1    // σ จากช่วงแท่ง High-Low (ปรับสเกลให้เฉลี่ยเท่าราคาปิด)
};

enum ENUM_THR_MODE {
   THR_FIXED = 0,   // เกณฑ์คงที่ (เหมือน EA)
   THR_PCT   = 1    // เกณฑ์ปรับตามตลาด (เปอร์เซ็นไทล์ย้อนหลัง)
};

//====================================================================
// 🎛️ INPUT PARAMETERS
//====================================================================
input group "=== Z (สูตรเดียวกับ Counter EA) ==="
input int             InpZ_Period          = 20;          // จำนวนแท่งของหน้าต่าง
input double          InpSigmaFloorMult    = 0.50;        // พื้นตัวหาร Z_reg = ค่านี้ × SD ของส่วนต่างต่อแท่ง
input ENUM_SIGMA_MODE InpSigmaMode         = SIG_CLOSE;   // ตัวหาร σ

input group "=== เกณฑ์ ==="
input ENUM_THR_MODE   InpThrMode           = THR_FIXED;   // เกณฑ์คงที่ / ปรับตามตลาด
input double          InpT2_Z              = 2.50;        // FIXED: T2 (ป้ายเริ่มแสดง, ต้องเกินทั้งคู่ถึงมีสี)
input double          InpT3_Z              = 3.00;        // FIXED: T3 (ตัวใดตัวหนึ่ง)
input double          InpT4_Z              = 3.50;        // FIXED: T4 (ตัวใดตัวหนึ่ง)
input double          InpFloatMin          = 1.80;        // T2 ต้องมี Z_float > ค่านี้ (เหมือน EA, T3/T4 ไม่ต้อง)
input double          InpT2EitherFloat     = 2.00;        // Z_float > ค่านี้ → T2 เกินตัวเดียวก็พอ (เหมือน EA)
input double          InpPctT2             = 1.0;         // PCT: T2 = Z ที่ top กี่ % ของแท่งย้อนหลัง
input double          InpPctT3             = 0.3;         // PCT: T3 = top กี่ %
input double          InpPctT4             = 0.1;         // PCT: T4 = top กี่ %
input int             InpPctDays           = 20;          // PCT: ย้อนหลังกี่วัน (นับเป็นวัน 24 ชม. ของ TF กราฟ)

input group "=== แสดงผล (แบบเดียวกับ Counter EA) ==="
input bool            InpShowBarZ          = true;        // ป้าย Z บนแท่งที่ Z เกินเกณฑ์ T2
input int             InpBarZBars          = 2000;        // ป้ายย้อนหลังกี่แท่ง (0 = ทั้งหมด)
input int             InpBarZFontSize      = 8;           // ขนาดตัวอักษรป้าย
input double          InpBarZOffset_Pts    = 300.0;       // ระยะห่างป้ายจากไส้เทียน (จุด)
input bool            InpShowFloatMark     = true;        // ป้าย Z_float (ราคาเปิดลอยพ้น SMA)
input double          InpFloatMarkZ        = 1.00;        // ป้าย Z_float: แสดงเมื่อ |Z_float| > ค่านี้ (แท่งปัจจุบันแสดงเสมอ)
input bool            InpShowLevelLines    = true;        // เส้นแนวนอนระดับ Z ปัจจุบัน (เส้นถดถอย / SMA20 ± เกณฑ์ T2)
input bool            InpShowLiveZ         = true;        // ป้าย Z สดที่ขอบขวา
input int             InpLiveZFontSize     = 11;          // ขนาดตัวอักษรป้าย Z สด
input int             InpLiveZOffsetPx     = 10;          // ระยะป้าย Z สดจากขอบขวา (พิกเซล)
input bool            InpShowHistLines     = false;       // เส้นย้อนหลัง: เส้นถดถอย / SMA20 ± เกณฑ์ T2 ทุกแท่ง
input bool            InpShowMonthTable    = true;        // ตารางอัตราการเกิดรายเดือน (มุมขวาล่าง)
input int             InpMonthRows         = 12;          // แสดงกี่เดือนล่าสุด

input group "=== สี (เหมือน Counter EA) ==="
input color           InpClrZCenter        = clrGold;           // เส้นกลาง Regression
input color           InpClrZSellLine      = clrOrangeRed;      // Regression ระดับ SELL
input color           InpClrZBuyLine       = clrAqua;           // Regression ระดับ BUY
input color           InpClrSmaCenter      = clrDarkKhaki;      // SMA20
input color           InpClrSmaSellLine    = clrLightSalmon;    // SMA20 ระดับ SELL
input color           InpClrSmaBuyLine     = clrPaleTurquoise;  // SMA20 ระดับ BUY
input color           InpClrBarZSell       = clrOrangeRed;      // ป้าย Z ฝั่ง SELL (เหนือแท่ง)
input color           InpClrBarZBuy        = clrDeepSkyBlue;    // ป้าย Z ฝั่ง BUY (ใต้แท่ง)
input color           InpClrBarZOther      = clrGray;           // ป้าย Z ที่ไม่เข้าระดับ
input color           InpClrFloatMark      = clrMediumPurple;   // ป้าย Z_float
input color           InpClrLiveSell       = clrOrangeRed;      // ป้าย Z สด: ถึงเกณฑ์ SELL
input color           InpClrLiveBuy        = clrDeepSkyBlue;    // ป้าย Z สด: ถึงเกณฑ์ BUY
input color           InpClrLiveNear       = clrGold;           // ป้าย Z สด: ใกล้เกณฑ์
input color           InpClrLiveNormal     = clrSilver;         // ป้าย Z สด: ปกติ
input color           InpClrTable          = clrSilver;         // ตารางรายเดือน

//====================================================================
// 🔒 INTERNAL
//====================================================================
const string PFX       = "7LCTX_";
const double NEAR_ZONE = 0.5;
#define NB   801          // ช่องฮิสโตแกรมของ Z สุดขั้ว: 0.00 - 8.00 ทีละ 0.01
#define BINW 0.01

double bR[], bRp[], bRm[], bS[], bSp[], bSm[];
double cThr2[], cThr3[], cThr4[];   // เกณฑ์ PCT ของแต่ละแท่ง (จากแท่งที่ปิดก่อนหน้า)
double cKr[], cKs[];                // ตัวปรับสเกลโหมด RANGE (σ_ราคาปิด ÷ σ_ช่วงแท่ง, EMA)

double   g_pmult = 1.0;
int      g_warm  = 0;
int      g_win   = 0;               // จำนวนแท่งของหน้าต่าง PCT
double   g_alpha = 0.0;             // EMA ของตัวปรับสเกล

// หน้าต่างเลื่อนของ Z สุดขั้ว (PCT)
int      g_hist[NB];
int      g_ring[];
int      g_ring_n = 0, g_ring_pos = 0;
int      g_next_push = 0;           // แท่งปิดถัดไปที่ยังไม่ได้นับ (หน้าต่าง + ตารางรายเดือน)
double   g_q2 = 0.0, g_q3 = 0.0, g_q4 = 0.0;   // เกณฑ์ PCT ล่าสุดของหน้าต่าง

// ตารางรายเดือน
int      g_m_key[];                 // ปี × 12 + เดือน
int      g_m_n[], g_m_c20[], g_m_c25[], g_m_c30[], g_m_b25[];
int      g_m_hist[];                // ฮิสโตแกรมของแต่ละเดือน (เดือน × NB)
bool     g_table_dirty = true;

// ป้าย Z สด
string   g_live_text = "";
color    g_live_clr  = clrSilver;
double   g_live_bid  = 0.0;
string   g_live_tip  = "";

//====================================================================
// 🧰 HELPERS
//====================================================================
double PtsToPrice(double pts) { return pts * g_pmult * _Point; }
double PriceToPts(double px)  { return px / (g_pmult * _Point); }

// Z แบบ EA (ตัวหารจากราคาปิด): ราคาปิด c[i−n+1 .. i−1] + ราคา P
bool ZCore(const double &c[], int i, double P, double &fit, double &sig_r, double &mean, double &sd_s) {
   int n = InpZ_Period;
   if(i - n + 1 < 1) return false;
   double ref = c[i - 1];
   double sy = 0.0, sxy = 0.0, syy = 0.0, sd = 0.0, sdd = 0.0;
   for(int k = 0; k < n - 1; k++) {
      int    idx = i - n + 1 + k;
      double y   = c[idx] - ref;
      sy += y; sxy += k * y; syy += y * y;
      if(k > 0) { double d = c[idx] - c[idx - 1]; sd += d; sdd += d * d; }
   }
   double yP = P - ref;
   sy += yP; sxy += (n - 1) * yP; syy += yP * yP;
   double d0 = P - c[i - 1];
   sd += d0; sdd += d0 * d0;

   double nn  = (double)n;
   double sx  = nn * (nn - 1.0) / 2.0;
   double sxx = (nn - 1.0) * nn * (2.0 * nn - 1.0) / 6.0;
   double mn  = sy / nn;
   double vs  = syy / nn - mn * mn;
   if(vs <= 0.0) return false;
   double b   = (nn * sxy - sx * sy) / (nn * sxx - sx * sx);
   double a   = (sy - b * sx) / nn;
   double ssr = syy - a * sy - b * sxy;
   if(ssr < 0.0) ssr = 0.0;
   double m   = nn - 1.0, md = sd / m, vd = sdd / m - md * md;
   double flo = (vd > 0.0) ? MathSqrt(vd) * InpSigmaFloorMult : 0.0;
   fit   = ref + a + b * (nn - 1.0);
   sig_r = MathMax(MathSqrt(ssr / nn), flo);
   mean  = ref + mn;
   sd_s  = MathSqrt(vs);
   return (sig_r > 0.0);
}

// σ จากช่วงแท่ง (Parkinson, หน่วยราคา) ของแท่งปิด n−1 แท่งก่อนแท่ง i
double RangeSigma(const double &h[], const double &l[], int i) {
   int    n = InpZ_Period;
   double s = 0.0;
   for(int k = i - n + 1; k <= i - 1; k++) { double r = h[k] - l[k]; s += r * r; }
   return MathSqrt(s / (4.0 * MathLog(2.0) * (n - 1)));
}

// Z ตามโหมดตัวหาร: คืนค่า Z_reg / Z_SMA + เส้นกลาง / ตัวหารที่ใช้จริง
bool ZAt(const double &c[], const double &h[], const double &l[], int i, double P,
         double &zr, double &zs, double &fit, double &sr, double &mean, double &ss) {
   double sig_r, sd_s;
   if(!ZCore(c, i, P, fit, sig_r, mean, sd_s)) return false;
   sr = sig_r; ss = sd_s;
   if(InpSigmaMode == SIG_RANGE && i >= 1 && cKr[i - 1] > 0.0 && cKs[i - 1] > 0.0) {
      double sp = RangeSigma(h, l, i);
      if(sp > 0.0) { sr = cKr[i - 1] * sp; ss = cKs[i - 1] * sp; }
   }
   zr = (P - fit) / sr;
   zs = (P - mean) / ss;
   return true;
}

int BinOf(double z) {
   int b = (int)MathFloor(MathMax(0.0, z) / BINW);
   return MathMin(b, NB - 1);
}

// ค่า Z ที่ top InpPctT2 / T3 / T4 % ของฮิสโตแกรม (ไล่จากช่องบนสุดลงมารอบเดียว)
void Quantiles3(const int &hist[], int base, int total, double &q2, double &q3, double &q4) {
   q2 = 0.0; q3 = 0.0; q4 = 0.0;
   if(total <= 0) return;
   int n2 = (int)MathMax(1.0, MathCeil(total * InpPctT2 / 100.0));
   int n3 = (int)MathMax(1.0, MathCeil(total * InpPctT3 / 100.0));
   int n4 = (int)MathMax(1.0, MathCeil(total * InpPctT4 / 100.0));
   int acc = 0;
   for(int b = NB - 1; b >= 0; b--) {
      acc += hist[base + b];
      if(q4 == 0.0 && acc >= n4) q4 = b * BINW;
      if(q3 == 0.0 && acc >= n3) q3 = b * BINW;
      if(acc >= n2) { q2 = b * BINW; return; }
   }
}

// % ของหน้าต่าง PCT ที่ Z สุดขั้ว > z
double PctAbove(double z) {
   if(g_ring_n <= 0) return 0.0;
   int cnt = 0;
   for(int b = BinOf(z) + 1; b < NB; b++) cnt += g_hist[b];
   return 100.0 * cnt / g_ring_n;
}

void WindowPush(double e) {
   int b = BinOf(e);
   if(g_ring_n < g_win) { g_ring[g_ring_n] = b; g_ring_n++; g_hist[b]++; }
   else {
      g_hist[g_ring[g_ring_pos]]--;
      g_ring[g_ring_pos] = b;
      g_hist[b]++;
      g_ring_pos = (g_ring_pos + 1) % g_win;
   }
   Quantiles3(g_hist, 0, g_ring_n, g_q2, g_q3, g_q4);
}

void MonthAdd(datetime t, double e, double eb) {
   MqlDateTime d;
   TimeToStruct(t, d);
   int key = d.year * 12 + (d.mon - 1);
   int m   = ArraySize(g_m_key) - 1;
   if(m < 0 || g_m_key[m] != key) {
      m++;
      ArrayResize(g_m_key, m + 1); ArrayResize(g_m_n, m + 1); ArrayResize(g_m_c20, m + 1);
      ArrayResize(g_m_c25, m + 1); ArrayResize(g_m_c30, m + 1); ArrayResize(g_m_b25, m + 1);
      ArrayResize(g_m_hist, (m + 1) * NB);
      g_m_key[m] = key; g_m_n[m] = 0; g_m_c20[m] = 0; g_m_c25[m] = 0; g_m_c30[m] = 0; g_m_b25[m] = 0;
      for(int b = 0; b < NB; b++) g_m_hist[m * NB + b] = 0;
   }
   g_m_n[m]++;
   if(e > 2.0)  g_m_c20[m]++;
   if(e > 2.5)  g_m_c25[m]++;
   if(e > 3.0)  g_m_c30[m]++;
   if(eb > 2.5) g_m_b25[m]++;
   g_m_hist[m * NB + BinOf(e)]++;
   g_table_dirty = true;
}

void ResetStats() {
   ArrayInitialize(g_hist, 0);
   ArrayResize(g_ring, g_win);
   g_ring_n = 0; g_ring_pos = 0;
   g_next_push = 0;
   g_q2 = 0.0; g_q3 = 0.0; g_q4 = 0.0;
   ArrayResize(g_m_key, 0); ArrayResize(g_m_n, 0); ArrayResize(g_m_c20, 0); ArrayResize(g_m_c25, 0);
   ArrayResize(g_m_c30, 0); ArrayResize(g_m_b25, 0); ArrayResize(g_m_hist, 0);
   g_table_dirty = true;
}

// เกณฑ์ T2 / T3 / T4 ของแท่ง i ตามโหมด
void Thresholds(int i, double &t2, double &t3, double &t4) {
   if(InpThrMode == THR_PCT && cThr2[i] > 0.0) { t2 = cThr2[i]; t3 = MathMax(cThr3[i], t2); t4 = MathMax(cThr4[i], t3); return; }
   t2 = InpT2_Z; t3 = InpT3_Z; t4 = InpT4_Z;
}

string ModeText() {
   return (InpSigmaMode == SIG_RANGE ? "σ ช่วงแท่ง" : "σ ราคาปิด") + " | " + (InpThrMode == THR_PCT ? "เกณฑ์ปรับตามตลาด" : "เกณฑ์คงที่");
}

//====================================================================
// 🏷️ ป้ายบนแท่ง (แบบเดียวกับ Counter EA)
//====================================================================
// Z_float ของแท่ง i (บวก = ราคาเปิดเหนือ SMA ตอนเปิดแท่ง)
bool FloatZ(int i, const double &open[], const double &high[], const double &low[], const double &close[],
            double &fz, double &mean, double &ss) {
   double zr, zs, fit, sr;
   fz = 0.0;
   if(!ZAt(close, high, low, i, open[i], zr, zs, fit, sr, mean, ss)) return false;
   fz = (open[i] - mean) / ss;
   return true;
}

void BarZLabels(int i, const datetime &time[], const double &open[], const double &high[], const double &low[], const double &close[]) {
   double off = PtsToPrice(InpBarZOffset_Pts);
   string ts  = IntegerToString((long)time[i]);
   double t2, t3, t4, fz, fmean, fss;
   Thresholds(i, t2, t3, t4);
   FloatZ(i, open, high, low, close, fz, fmean, fss);
   for(int side = 0; side < 2; side++) {
      string name = PFX + (side == 0 ? "ZL_S_" : "ZL_B_") + ts;
      double P    = (side == 0) ? high[i] : low[i];
      double zr, zs, fit, sr, mean, ss;
      bool   ok   = ZAt(close, high, low, i, P, zr, zs, fit, sr, mean, ss);
      double a_r  = (side == 0) ? zr : -zr, a_s = (side == 0) ? zs : -zs;
      bool   hit_r = ok && a_r > t2, hit_s = ok && a_s > t2;
      if(!InpShowBarZ || !(hit_r || hit_s)) { if(ObjectFind(0, name) >= 0) ObjectDelete(0, name); continue; }

      // ระดับแบบ EA: T4 / T3 ตัวใดตัวหนึ่ง (ไม่ต้องลอย) | T2 ทั้งคู่ + Z_float > ขั้นต่ำ (ลอยมากพอ → ตัวเดียวก็ได้)
      double hi = MathMax(a_r, a_s), lo = MathMin(a_r, a_s);
      double zf = (side == 0) ? fz : -fz;
      bool   t2ok = zf > InpFloatMin && (lo > t2 || (zf > InpT2EitherFloat && hi > t2));
      int    tier = (hi > t4) ? 4 : (hi > t3) ? 3 : t2ok ? 2 : 0;
      color  clr  = (tier == 0) ? InpClrBarZOther : (side == 0 ? InpClrBarZSell : InpClrBarZBuy);
      double y    = (side == 0) ? (high[i] + off) : (low[i] - off);
      if(ObjectFind(0, name) < 0) {
         ObjectCreate(0, name, OBJ_TEXT, 0, time[i], y);
         ObjectSetString(0,  name, OBJPROP_FONT, "Arial Bold");
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpBarZFontSize);
         ObjectSetInteger(0, name, OBJPROP_ANCHOR, (side == 0) ? ANCHOR_LOWER : ANCHOR_UPPER);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      }
      ObjectSetDouble(0,  name, OBJPROP_PRICE, y);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetString(0,  name, OBJPROP_TEXT, StringFormat("R%+.2f | S%+.2f", zr, zs));
      ObjectSetString(0,  name, OBJPROP_TOOLTIP,
                      StringFormat("%s | ที่ %s: Z_reg %+.2f%s / Z_SMA %+.2f%s | Z_float %+.2f | %s | เกณฑ์ T2 %.2f / T3 %.2f / T4 %.2f (%s)",
                                   TimeToString(time[i], TIME_DATE|TIME_MINUTES), (side == 0 ? "High" : "Low"),
                                   zr, (hit_r ? " ✓" : ""), zs, (hit_s ? " ✓" : ""), zf,
                                   (tier > 0 ? "ถึงระดับ T" + IntegerToString(tier) : "ถึงเกณฑ์ไม่ครบ"), t2, t3, t4, ModeText()));
   }
}

// ป้าย Z_float: (ราคาเปิด − SMA ตอนเปิดแท่ง) ÷ SD — เหนือ SMA = ป้ายใต้ Low (ฝั่ง SELL) / ใต้ SMA = ป้ายเหนือ High (ฝั่ง BUY)
void FloatLabel(int i, bool live, const datetime &time[], const double &open[], const double &high[], const double &low[], const double &close[]) {
   double off = PtsToPrice(InpBarZOffset_Pts);
   string ts  = IntegerToString((long)time[i]);
   double fz, mean, ss;
   bool   ok  = FloatZ(i, open, high, low, close, fz, mean, ss);
   for(int side = 0; side < 2; side++) {
      string name = PFX + (side == 0 ? "FL_S_" : "FL_B_") + ts;
      double zf   = (side == 0) ? fz : -fz;
      bool   hit  = zf > InpFloatMarkZ;
      if(!InpShowFloatMark || !ok || !(hit || (live && zf > 0.0))) { if(ObjectFind(0, name) >= 0) ObjectDelete(0, name); continue; }
      double y = (side == 0) ? (low[i] - off) : (high[i] + off);
      if(ObjectFind(0, name) < 0) {
         ObjectCreate(0, name, OBJ_TEXT, 0, time[i], y);
         ObjectSetString(0,  name, OBJPROP_FONT, "Arial Bold");
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpBarZFontSize);
         ObjectSetInteger(0, name, OBJPROP_ANCHOR, (side == 0) ? ANCHOR_UPPER : ANCHOR_LOWER);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      }
      ObjectSetDouble(0,  name, OBJPROP_PRICE, y);
      ObjectSetInteger(0, name, OBJPROP_COLOR, hit ? InpClrFloatMark : InpClrBarZOther);
      ObjectSetString(0,  name, OBJPROP_TEXT, StringFormat("F%+.2f", zf));
      ObjectSetString(0,  name, OBJPROP_TOOLTIP,
                      StringFormat("%s | ราคาเปิดลอยพ้น SMA (%s): Z_float %+.2f = (Open %s − SMA ตอนเปิดแท่ง %s) ÷ σ %.0f จุด (%s)",
                                   TimeToString(time[i], TIME_DATE|TIME_MINUTES), (side == 0 ? "ฝั่ง SELL" : "ฝั่ง BUY"), zf,
                                   DoubleToString(open[i], _Digits), DoubleToString(mean, _Digits), PriceToPts(ss), ModeText()));
   }
}

//====================================================================
// 📏 เส้นระดับ / ป้าย Z สด / ตารางรายเดือน
//====================================================================
void HLine(string name, double price, color clr, ENUM_LINE_STYLE style, string tip) {
   string nm = PFX + name;
   if(!InpShowLevelLines || price <= 0.0) { if(ObjectFind(0, nm) >= 0) ObjectDelete(0, nm); return; }
   if(ObjectFind(0, nm) < 0) {
      ObjectCreate(0, nm, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, nm, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, nm, OBJPROP_STYLE, style);
      ObjectSetInteger(0, nm, OBJPROP_BACK, true);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
   }
   ObjectSetDouble(0, nm, OBJPROP_PRICE, price);
   ObjectSetString(0, nm, OBJPROP_TOOLTIP, tip);
}

void DrawLiveZ() {
   string nm = PFX + "LIVE_Z";
   if(!InpShowLiveZ || g_live_text == "") { if(ObjectFind(0, nm) >= 0) ObjectDelete(0, nm); return; }
   int x = 0, y = 0;
   if(!ChartTimePriceToXY(0, 0, iTime(_Symbol, PERIOD_CURRENT, 0), g_live_bid, x, y)) return;
   int h = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   y = MathMax(8, MathMin(h - 8, y));
   if(ObjectFind(0, nm) < 0) {
      ObjectCreate(0, nm, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, nm, OBJPROP_ANCHOR, ANCHOR_RIGHT);
      ObjectSetString(0,  nm, OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, InpLiveZFontSize);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
   }
   ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, MathMax(0, InpLiveZOffsetPx));
   ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, y);
   ObjectSetString(0,  nm, OBJPROP_TEXT, g_live_text);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, g_live_clr);
   ObjectSetString(0,  nm, OBJPROP_TOOLTIP, g_live_tip);
}

void TableLine(int row, string text) {
   string nm = PFX + "MT_" + IntegerToString(row);
   if(ObjectFind(0, nm) < 0) {
      ObjectCreate(0, nm, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_RIGHT_LOWER);
      ObjectSetInteger(0, nm, OBJPROP_ANCHOR, ANCHOR_RIGHT_LOWER);
      ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, 12 + row * 15);
      ObjectSetString(0,  nm, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, nm, OBJPROP_COLOR, InpClrTable);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
   }
   ObjectSetString(0, nm, OBJPROP_TEXT, text);
}

void DrawMonthTable() {
   if(!InpShowMonthTable || !g_table_dirty) return;
   g_table_dirty = false;
   ObjectsDeleteAll(0, PFX + "MT_");
   int nm   = ArraySize(g_m_key);
   int show = MathMin(nm, MathMax(1, InpMonthRows));
   int row  = 0;
   // บรรทัดล่างสุด: เกณฑ์ปรับตามตลาดตอนนี้ + เกณฑ์คงที่เทียบเป็น top กี่ %
   TableLine(row++, StringFormat("เกณฑ์ปรับตามตลาด %d วัน: T2 > %.2f / T3 > %.2f / T4 > %.2f (top %.1f / %.1f / %.1f%%) | คงที่ %.1f / %.1f / %.1f = top %.2f / %.2f / %.2f%%",
                                 InpPctDays, g_q2, g_q3, g_q4, InpPctT2, InpPctT3, InpPctT4,
                                 InpT2_Z, InpT3_Z, InpT4_Z, PctAbove(InpT2_Z), PctAbove(InpT3_Z), PctAbove(InpT4_Z)));
   for(int m = nm - 1; m >= nm - show; m--) {
      double n = MathMax(1, g_m_n[m]), q2, q3, q4;
      Quantiles3(g_m_hist, m * NB, g_m_n[m], q2, q3, q4);
      TableLine(row++, StringFormat("%04d-%02d %6d %6.2f%% %6.2f%% %6.2f%% %7.2f%%  | %5.2f %5.2f %5.2f",
                                    g_m_key[m] / 12, g_m_key[m] % 12 + 1, g_m_n[m],
                                    100.0 * g_m_c20[m] / n, 100.0 * g_m_c25[m] / n, 100.0 * g_m_c30[m] / n, 100.0 * g_m_b25[m] / n,
                                    q2, q3, q4));
   }
   TableLine(row++, StringFormat("เดือน     แท่ง   Z>2.0   Z>2.5   Z>3.0 ทั้งคู่>2.5  | top%.1f%% %.1f%% %.1f%%", InpPctT2, InpPctT3, InpPctT4));
   TableLine(row++, "📅 อัตราการเกิด Z ต่อแท่ง (Z_reg หรือ Z_SMA ที่ High / Low) | " + ModeText());
}

//====================================================================
// 🚀 EVENT HANDLERS
//====================================================================
void SetPlot(int plot, color clr) {
   if(!InpShowHistLines) PlotIndexSetInteger(plot, PLOT_DRAW_TYPE, DRAW_NONE);
   PlotIndexSetInteger(plot, PLOT_LINE_COLOR, clr);
   PlotIndexSetInteger(plot, PLOT_DRAW_BEGIN, g_warm);
   PlotIndexSetDouble(plot, PLOT_EMPTY_VALUE, EMPTY_VALUE);
}

int OnInit() {
   if(InpZ_Period < 5 || InpSigmaFloorMult < 0.0 || InpT2_Z <= 0.0 || InpT3_Z < InpT2_Z || InpT4_Z < InpT3_Z ||
      InpFloatMin < 0.0 || InpPctT2 <= 0.0 || InpPctT3 <= 0.0 || InpPctT4 <= 0.0 || InpPctT2 > 50.0 || InpPctDays < 1 || InpBarZBars < 0 || InpMonthRows < 1) {
      Print("❌ ค่า Input ไม่ถูกต้อง (หน้าต่าง ≥ 5, T2 ≤ T3 ≤ T4, เปอร์เซ็นต์ 0-50, วัน ≥ 1)");
      return(INIT_PARAMETERS_INCORRECT);
   }
   g_pmult = (_Digits == 2 || _Digits == 4) ? 0.1 : 1.0;
   g_warm  = InpZ_Period + 2;
   int bars = (int)((long)InpPctDays * 86400 / MathMax(60, PeriodSeconds(_Period)));
   g_win   = MathMax(100, bars);
   g_alpha = 2.0 / (g_win + 1.0);

   SetIndexBuffer(0,  bR,    INDICATOR_DATA);
   SetIndexBuffer(1,  bRp,   INDICATOR_DATA);
   SetIndexBuffer(2,  bRm,   INDICATOR_DATA);
   SetIndexBuffer(3,  bS,    INDICATOR_DATA);
   SetIndexBuffer(4,  bSp,   INDICATOR_DATA);
   SetIndexBuffer(5,  bSm,   INDICATOR_DATA);
   SetIndexBuffer(6,  cThr2, INDICATOR_CALCULATIONS);
   SetIndexBuffer(7,  cThr3, INDICATOR_CALCULATIONS);
   SetIndexBuffer(8,  cThr4, INDICATOR_CALCULATIONS);
   SetIndexBuffer(9,  cKr,   INDICATOR_CALCULATIONS);
   SetIndexBuffer(10, cKs,   INDICATOR_CALCULATIONS);
   SetPlot(0, InpClrZCenter);
   SetPlot(1, InpClrZSellLine);
   SetPlot(2, InpClrZBuyLine);
   SetPlot(3, InpClrSmaCenter);
   SetPlot(4, InpClrSmaSellLine);
   SetPlot(5, InpClrSmaBuyLine);

   IndicatorSetString(INDICATOR_SHORTNAME, "7L Z SMA / Reg");
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
   ObjectsDeleteAll(0, PFX);
   ResetStats();
   g_live_text = "";
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
   ObjectsDeleteAll(0, PFX);
}

int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[], const double &high[], const double &low[],
                const double &close[], const long &tick_volume[], const long &volume[], const int &spread[]) {
   if(rates_total < g_warm + 5) return(0);
   int start = (prev_calculated > 0) ? prev_calculated - 1 : 0;
   if(start == 0) {
      ObjectsDeleteAll(0, PFX + "ZL_");
      ObjectsDeleteAll(0, PFX + "FL_");
      ResetStats();
   }
   int last = rates_total - 1;
   int from = (InpBarZBars > 0) ? MathMax(g_warm, rates_total - InpBarZBars) : g_warm;

   for(int i = start; i < rates_total; i++) {
      bR[i] = EMPTY_VALUE; bRp[i] = EMPTY_VALUE; bRm[i] = EMPTY_VALUE;
      bS[i] = EMPTY_VALUE; bSp[i] = EMPTY_VALUE; bSm[i] = EMPTY_VALUE;
      // เกณฑ์ PCT ของแท่งนี้ = จากหน้าต่างของแท่งที่ปิดก่อนหน้า (ไม่มองอนาคต)
      bool full = (g_ring_n >= MathMin(g_win, 200));
      cThr2[i] = full ? g_q2 : 0.0;
      cThr3[i] = full ? g_q3 : 0.0;
      cThr4[i] = full ? g_q4 : 0.0;
      cKr[i]   = (i > 0) ? cKr[i - 1] : 0.0;
      cKs[i]   = (i > 0) ? cKs[i - 1] : 0.0;
      if(i < g_warm) continue;

      // ตัวปรับสเกลโหมด RANGE: อัปเดตเมื่อแท่งปิดแล้วเท่านั้น
      double fit0, sig_r0, mean0, sd_s0;
      bool   core = ZCore(close, i, close[i], fit0, sig_r0, mean0, sd_s0);
      if(core && i < last) {
         double sp = RangeSigma(high, low, i);
         if(sp > 0.0) {
            double rr = sig_r0 / sp, rs = sd_s0 / sp;
            cKr[i] = (cKr[i - 1] > 0.0) ? cKr[i - 1] + g_alpha * (rr - cKr[i - 1]) : rr;
            cKs[i] = (cKs[i - 1] > 0.0) ? cKs[i - 1] + g_alpha * (rs - cKs[i - 1]) : rs;
         }
      }

      // เส้นย้อนหลัง (ณ ราคาปิด) ± เกณฑ์ T2
      double zr, zs, fit, sr, mean, ss, t2, t3, t4;
      Thresholds(i, t2, t3, t4);
      if(ZAt(close, high, low, i, close[i], zr, zs, fit, sr, mean, ss)) {
         bR[i] = fit;  bRp[i] = fit + t2 * sr;  bRm[i] = fit - t2 * sr;
         bS[i] = mean; bSp[i] = mean + t2 * ss; bSm[i] = mean - t2 * ss;
      }

      // Z สุดขั้วของแท่ง (ตัวใดตัวหนึ่ง / ทั้งคู่) → หน้าต่าง PCT + ตารางรายเดือน (แท่งปิดแล้ว นับครั้งเดียว)
      if(i < last && i >= g_next_push) {
         double hr, hs, lr, ls, f1, s1, m1, q1;
         bool okh = ZAt(close, high, low, i, high[i], hr, hs, f1, s1, m1, q1);
         bool okl = ZAt(close, high, low, i, low[i],  lr, ls, f1, s1, m1, q1);
         if(okh && okl) {
            double e  = MathMax(MathMax(hr, hs), MathMax(-lr, -ls));
            double eb = MathMax(MathMin(hr, hs), MathMin(-lr, -ls));
            WindowPush(e);
            MonthAdd(time[i], e, eb);
         }
         g_next_push = i + 1;
      }

      // ป้ายบนแท่ง (แท่งปัจจุบันประเมินใหม่ทุก Tick)
      if(i >= from) {
         BarZLabels(i, time, open, high, low, close);
         FloatLabel(i, (i == last), time, open, high, low, close);
      }
   }
   // ลบป้ายที่หลุดช่วงแสดง
   if(InpBarZBars > 0 && prev_calculated > 0 && rates_total > prev_calculated) {
      for(int k = MathMax(0, prev_calculated - InpBarZBars - 1); k < from; k++) {
         string ts = IntegerToString((long)time[k]);
         ObjectDelete(0, PFX + "ZL_S_" + ts); ObjectDelete(0, PFX + "ZL_B_" + ts);
         ObjectDelete(0, PFX + "FL_S_" + ts); ObjectDelete(0, PFX + "FL_B_" + ts);
      }
   }

   // เส้นระดับ + ป้าย Z สด ณ ราคาล่าสุด
   double zr, zs, fit, sr, mean, ss, t2, t3, t4;
   Thresholds(last, t2, t3, t4);
   if(ZAt(close, high, low, last, close[last], zr, zs, fit, sr, mean, ss)) {
      HLine("R_MAIN", fit,            InpClrZCenter,     STYLE_DOT,     "[Regression] เส้นกลาง Z = 0");
      HLine("R_SELL", fit + t2 * sr,  InpClrZSellLine,   STYLE_DASH,    StringFormat("[Regression] SELL T2 Z > +%.2f (%s)", t2, ModeText()));
      HLine("R_BUY",  fit - t2 * sr,  InpClrZBuyLine,    STYLE_DASH,    StringFormat("[Regression] BUY T2 Z < −%.2f (%s)", t2, ModeText()));
      HLine("S_MAIN", mean,           InpClrSmaCenter,   STYLE_DOT,     "[SMA20] เส้นกลาง Z = 0");
      HLine("S_SELL", mean + t2 * ss, InpClrSmaSellLine, STYLE_DASHDOT, StringFormat("[SMA20] SELL T2 Z > +%.2f (%s)", t2, ModeText()));
      HLine("S_BUY",  mean - t2 * ss, InpClrSmaBuyLine,  STYLE_DASHDOT, StringFormat("[SMA20] BUY T2 Z < −%.2f (%s)", t2, ModeText()));
      double z = (MathAbs(zr) >= MathAbs(zs)) ? zr : zs;
      g_live_clr  = (z > t2) ? InpClrLiveSell : (z < -t2) ? InpClrLiveBuy
                  : (MathAbs(z) >= t2 - NEAR_ZONE) ? InpClrLiveNear : InpClrLiveNormal;
      g_live_text = StringFormat("R %+.2f | S %+.2f ▶", zr, zs);
      g_live_bid  = close[last];
      g_live_tip  = StringFormat("Z_reg %+.3f (กลาง %s) | Z_SMA %+.3f (SMA20 %s) | เกณฑ์ T2 %.2f / T3 %.2f / T4 %.2f | %s",
                                 zr, DoubleToString(fit, _Digits), zs, DoubleToString(mean, _Digits), t2, t3, t4, ModeText());
      DrawLiveZ();
   }
   DrawMonthTable();
   return(rates_total);
}

// เลื่อน/ซูมกราฟ → จัดตำแหน่งป้าย Z สดใหม่
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
   if(id != CHARTEVENT_CHART_CHANGE) return;
   DrawLiveZ();
   ChartRedraw(0);
}
//+------------------------------------------------------------------+
