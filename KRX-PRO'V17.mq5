//+------------------------------------------------------------------+
//|                                        Kiroix EA_LicenseGuard.mq5|
//|                                       Copyright 2026, KiroiX Labs|
//|                                   https://t.me/+hUjqUSGjgek4YmZl |
//+------------------------------------------------------------------+
#property copyright "Arwan RM-group™"
#property link      "https://t.me/+hUjqUSGjgek4YmZl"
#property version   "1.17"
#property description "HIGH RISK - NO STOP LOSS - GRID MARTINGALE + LICENSE GUARD"
#property description "Exness/Valetax XAUUSD Specific: 2/3 Digits, 30 pips = 3.000 price"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//--- Enums
enum ENUM_TRADE_DIR {
   DIR_BUY,       // Buy Only
   DIR_SELL,      // Sell Only
   DIR_AUTO       // Auto (Follow Prev Candle Close)
};

//--- Input Parameters (Original Grid)
input group "=== Volume & Grid Settings ==="
input double         InitialLot           = 0.01;      // Initial Lot Size
input double         LotMultiplier        = 1.1;       // Lot Multiplier (Grid)
input double         GridPips             = 30.0;      // Grid Distance (Pips)
input int            MaxGridLayers        = 99;        // Max Grid Layers

input group "=== Take Profit Settings (Pips) ==="
input double         BasketProfitPips     = 44.0;      // Basket Profit (All Positions)
input double         TrendFollowTP_Pips   = 35.0;      // Trend Follow TP (Initial only)
input double         ScalpingTP_Pips      = 30.0;      // Scalping TP (Against trend)

input group "=== Daily Target & Time Filter ==="
input double         MaxDailyProfitUSD    = 10000.0;   // Max Daily Profit ($)
input bool           UseTimeFilter        = true;      // Enable Time Filter
input int            StartHour_GMT8       = 7;         // Start Hour (WITA / GMT+8)
input int            StartMinute          = 5;         // Start Minute
input int            StopHour_GMT8        = 23;        // Stop Hour (WITA / GMT+8)
input int            StopMinute           = 45;        // Stop Minute

input group "=== General Settings ==="
input ENUM_TRADE_DIR TradeDirection       = DIR_AUTO;  // Trade Direction
input ulong          MagicNumber          = 20260321;  // Magic Number
input ulong          Slippage             = 10;        // Slippage (Points)

//--- License Guard Input (Tambahan)
input group "=== License Guard Settings ==="
input string         InpLicenseKey        = "";        // License Key (KRX-XXXX-XXXX-XXXX)
input string         FirebaseDBURL        = "https://kiroi-x-ecosystem-default-rtdb.asia-southeast1.firebasedatabase.app/"; //firebase

//--- Global Variables (Original)
CTrade         trade;
CPositionInfo  pos;
double         g_CenterPrice     = 0.0;
int            g_CurrentLayer    = 0;
bool           g_DailyTargetHit  = false;
int            g_LastDayHit      = -1;
string         g_PrimaryDir      = ""; // "BUY" or "SELL"

const double   PIP_VALUE         = 0.100; // 1 pip = 0.100 price unit

//--- License Guard Global Variables
bool           g_LicenseValid    = false;
string         g_AccountNumber   = "";
string         g_BrokerServer    = "";
datetime       g_ExpiryDate      = 0;
datetime       g_LastLicenseCheck= 0;
bool           g_LicenseChecked  = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // --- License Guard Initialization ---
   g_AccountNumber = IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
   g_BrokerServer  = AccountInfoString(ACCOUNT_SERVER);
   Print("Account: ", g_AccountNumber, " | Broker: ", g_BrokerServer);
   
   // Validasi format license key sederhana
   if(StringLen(InpLicenseKey) != 19 || StringSubstr(InpLicenseKey,0,4) != "KRX-") {
      Alert("Format License Key salah! Harus KRX-XXXX-XXXX-XXXX");
      return(INIT_FAILED);
   }
   
   // Cek lisensi pertama kali
   if(!CheckLicense()) {
      Alert("LICENSE INVALID - Expert akan dihentikan.");
      return(INIT_FAILED);
   }
   
   // --- Original Grid Initialization ---
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);
   trade.SetTypeFillingBySymbol(_Symbol);
   
   CreateDashboard();
   Print("EA Initialized. HIGH RISK - NO STOP LOSS - GRID MARTINGALE + LICENSE GUARD ACTIVE.");
   
   // Set timer untuk heartbeat (5 menit = 300 detik)
   EventSetTimer(300);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   ObjectsDeleteAll(0, "DASH_");
}

//+------------------------------------------------------------------+
//| Timer function (Heartbeat setiap 5 menit)                        |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(g_LicenseValid) {
      UpdateHeartbeat();
   }
}

//+------------------------------------------------------------------+
//| Expert tick function (Original + License Guard)                  |
//+------------------------------------------------------------------+
void OnTick()
{
   // --- LICENSE GUARD: Cek ulang setiap hari baru ---
   static datetime lastDate = 0;
   datetime currentDate = iTime(_Symbol, PERIOD_D1, 0);
   if(currentDate != lastDate) {
      lastDate = currentDate;
      if(!CheckLicense()) {
         Alert("LICENSE INVALID - Lisensi tidak aktif atau expired. EA akan dihentikan.");
         ExpertRemove();
         return;
      }
   }
   
   // --- UPDATE DAILY SUMMARY (WITA 07:05 - 23:45) ---
   MqlDateTime tmLocal;
   TimeToStruct(TimeLocal(), tmLocal);
   int currentMins = tmLocal.hour * 60 + tmLocal.min;
   if(currentMins >= 7*60+5 && currentMins <= 23*60+45) {
      UpdateDailySummary();
   }
   
   // --- ORIGINAL GRID LOGIC (Tidak diubah) ---
   // 1. Reset Daily Target on New Day
   MqlDateTime dtLocal;
   TimeToStruct(TimeLocal(), dtLocal);
   if(dtLocal.day != g_LastDayHit) {
      g_DailyTargetHit = false;
   }

   // 2. Calculate current statistics
   int buyCount=0, sellCount=0;
   double buyLots=0, sellLots=0, totalFloating=0;
   for(int i=PositionsTotal()-1; i>=0; i--) {
      if(pos.SelectByIndex(i)) {
         if(pos.Magic() == MagicNumber && pos.Symbol() == _Symbol) {
            totalFloating += pos.Profit() + pos.Swap() + pos.Commission();
            if(pos.PositionType() == POSITION_TYPE_BUY) {
               buyCount++;
               buyLots += pos.Volume();
            } else if(pos.PositionType() == POSITION_TYPE_SELL) {
               sellCount++;
               sellLots += pos.Volume();
            }
         }
      }
   }
   
   int totalPos = buyCount + sellCount;
   
   // State Recovery
   if(totalPos == 0) {
      g_CenterPrice = 0.0;
      g_CurrentLayer = 0;
      g_PrimaryDir = "";
   } else if (g_CenterPrice == 0.0) {
      RecoverState();
   }

   // 3. Daily Profit Check
   double dailyClosedProfit = GetClosedProfitTodayLocal();
   if(!g_DailyTargetHit && dailyClosedProfit >= MaxDailyProfitUSD) {
      g_DailyTargetHit = true;
      g_LastDayHit = dtLocal.day;
      Print("Daily Target Hit! Pausing until tomorrow.");
   }

   // 4. Time Filter & Status Check
   bool isTradingTime = CheckTimeFilter(dtLocal);
   string status = "ACTIVE";
   
   if(g_DailyTargetHit) {
      if(totalPos > 0) status = "ACTIVE";
      else status = "PAUSED (Daily Target Hit)";
   }
   else if(UseTimeFilter && !isTradingTime) {
      if(totalPos > 0) status = "ACTIVE";
      else status = "PAUSED (Outside WITA Hours)";
   }

   // 5. Update Dashboard (tambahkan info lisensi)
   UpdateDashboard(status, buyCount, buyLots, sellCount, sellLots, totalFloating, dailyClosedProfit);

   // 6. Check Take Profits (Hidden)
   if(totalPos > 0) {
      CheckHiddenTPs(totalFloating, totalLots(buyLots, sellLots));
      // Re-evaluate positions after TP check
      totalPos = 0;
      for(int i=PositionsTotal()-1; i>=0; i--) {
         if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber) totalPos++;
      }
      if(totalPos == 0) return; // Everything closed
   }

   // 7. Trading Logic
   if(status == "ACTIVE") {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      
      // A. Open Initial Position
      if(totalPos == 0) {
         OpenInitialPosition(ask, bid);
      }
      // B. Grid Management
      else if(g_CurrentLayer < MaxGridLayers) {
         CheckAndOpenGrid(ask, bid);
      }
   }
}

//+------------------------------------------------------------------+
//| OPTIMIZED LICENSE GUARD FUNCTIONS                                |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| 3-Layer Guard via Firebase REST API                              |
//+------------------------------------------------------------------+
bool CheckLicense()
{
   if(MQLInfoInteger(MQL_TESTER)) { g_LicenseValid = true; return true; }

   string url = FirebaseDBURL + "licenses/" + g_AccountNumber + ".json";
   char post[], result[];
   string headers = "Content-Type: application/json\r\n";
   string result_headers; // Tambahan parameter wajib MQL5
   
   g_LicenseValid = false;
   int res = WebRequest("GET", url, headers, 5000, post, result, result_headers);
   
   if(res == -1) {
      Print("WebRequest Error -1: Pastikan URL Firebase ada di 'Allow WebRequest' MT5");
      return false; 
   }
   
   if(res != 200) {
      Print("WebRequest gagal. Kode: ", res, " | URL: ", url);
      SendAlert("Gagal terhubung ke server lisensi (Kode: " + IntegerToString(res) + ")");
      return false;
   }
   
   string response = CharArrayToString(result);
   if(response == "null" || response == "") return false;
   
   string licenseKey = GetJsonValue(response, "license_key");
   string broker     = GetJsonValue(response, "broker_server");
   string status     = GetJsonValue(response, "status");
   string expiryStr  = GetJsonValue(response, "expiry_date");
   
   if(licenseKey == "" || broker == "" || status == "") {
      Print("Data lisensi tidak lengkap: ", response);
      SendAlert("Data lisensi tidak valid");
      return false;
   }
   
   string currentBroker = AccountInfoString(ACCOUNT_SERVER);
   if(StringFind(broker, currentBroker) == -1 && StringFind(currentBroker, broker) == -1) {
      Print("Broker server mismatch! Firebase: ", broker, " | EA: ", currentBroker);
      SendAlert("Broker server tidak cocok dengan lisensi");
      return false;
   }
   
   if(status != "ACTIVE") {
      Print("Status lisensi: ", status);
      SendAlert("Lisensi tidak aktif (status: " + status + ")");
      return false;
   }
   
   long expiry = (long)StringToInteger(expiryStr);
   if(expiry != 0 && expiry <= (long)TimeCurrent()) {
      Print("Lisensi expired pada ", TimeToString((datetime)expiry));
      SendAlert("Lisensi sudah kedaluwarsa");
      return false;
   }
   
   g_ExpiryDate = (datetime)expiry;
   g_LicenseValid = true;
   Print("Lisensi VALID sampai ", TimeToString(g_ExpiryDate));
   return true;
}

//+------------------------------------------------------------------+
//| Update Heartbeat ke Firebase                                     |
//+------------------------------------------------------------------+
void UpdateHeartbeat()
{
   if(MQLInfoInteger(MQL_TESTER)) return;

   string url = FirebaseDBURL + "licenses/" + g_AccountNumber + "/last_heartbeat.json";
   string data = IntegerToString(TimeCurrent() * 1000); // milliseconds
   char post[], result[];
   string result_headers; // Tambahan parameter wajib MQL5
   
   StringToCharArray(data, post);
   int res = WebRequest("PUT", url, "", 5000, post, result, result_headers);
   if(res == 200) Print("Heartbeat updated");
   else Print("Gagal update heartbeat: ", res);
}

//+------------------------------------------------------------------+
//| Update Daily Summary (Disinkronisasi dengan Waktu Server MT5)    |
//+------------------------------------------------------------------+
void UpdateDailySummary()
{
   if(MQLInfoInteger(MQL_TESTER) || !g_LicenseValid) return;

   MqlDateTime tm;
   TimeCurrent(tm);
   string dateStr = StringFormat("%04d-%02d-%02d", tm.year, tm.mon, tm.day);
   
   string url = FirebaseDBURL + "licenses/" + g_AccountNumber + "/daily_summary/" + dateStr + ".json";
   
   datetime startOfDay = TimeCurrent() - (TimeCurrent() % 86400);
   datetime endOfDay   = startOfDay + 86400;
   HistorySelect(startOfDay, endOfDay);
   
   double totalLot = 0, totalPL = 0;
   int totalDeals = HistoryDealsTotal();
   for(int i=0; i<totalDeals; i++) {
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == MagicNumber && 
         HistoryDealGetString(ticket, DEAL_SYMBOL) == _Symbol) {
         
         double lot = HistoryDealGetDouble(ticket, DEAL_VOLUME);
         double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT) +
                         HistoryDealGetDouble(ticket, DEAL_SWAP) +
                         HistoryDealGetDouble(ticket, DEAL_COMMISSION);
         if(HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT) {
            totalLot += lot;
            totalPL += profit;
         }
      }
   }
   
   string updateData = StringFormat("{\"lot_total\":%.2f,\"profit_loss\":%.2f,\"start_time\":\"00:00 (Server)\",\"last_update\":\"%s\"}", 
                                     totalLot, totalPL, TimeToString(TimeCurrent()));
   char post[], result[];
   string result_headers; // Tambahan parameter wajib MQL5
   
   StringToCharArray(updateData, post);
   int res = WebRequest("PATCH", url, "Content-Type: application/json\r\n", 5000, post, result, result_headers);
   if(res == 200) Print("Daily summary updated for ", dateStr);
   else Print("Gagal update daily summary: ", res);
}

//+------------------------------------------------------------------+
//| Kirim Alert ke Firebase                                          |
//+------------------------------------------------------------------+
void SendAlert(string message)
{
   if(MQLInfoInteger(MQL_TESTER)) return;

   string url = FirebaseDBURL + "alerts/" + g_AccountNumber + ".json";
   string data = StringFormat("{\"message\":\"%s\",\"timestamp\":%d,\"type\":\"error\"}", 
                               message, TimeCurrent()*1000);
   char post[], result[];
   string result_headers; // Tambahan parameter wajib MQL5
   
   StringToCharArray(data, post);
   WebRequest("POST", url, "Content-Type: application/json\r\n", 3000, post, result, result_headers);
}
//+------------------------------------------------------------------+
//| Helper: Ekstrak nilai dari JSON (Toleransi Spasi/Karakter Lain)  |
//+------------------------------------------------------------------+
string GetJsonValue(string json, string key)
{
   string search = "\"" + key + "\":";
   int idx = StringFind(json, search); // Mengganti nama variabel 'pos' menjadi 'idx' agar tidak bentrok
   if(idx == -1) return "";
   
   idx += StringLen(search);
   
   while(idx < StringLen(json) && (StringSubstr(json, idx, 1) == " " || StringSubstr(json, idx, 1) == ":")) idx++;
   
   string delimiter = (StringSubstr(json, idx, 1) == "\"") ? "\"" : "";
   if(delimiter == "\"") idx++;
   
   int end = StringFind(json, (delimiter == "" ? "," : delimiter), idx);
   if(end == -1) end = StringFind(json, "}", idx);
   if(end == -1) end = StringLen(json);
   
   return StringSubstr(json, idx, end - idx);
}

//+------------------------------------------------------------------+
//| ORIGINAL GRID FUNCTIONS (Tidak ada perubahan logika)             |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Open Initial Position                                            |
//+------------------------------------------------------------------+
void OpenInitialPosition(double ask, double bid)
{
   int dir = TradeDirection;
   if(dir == DIR_AUTO) {
      double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
      double open1 = iOpen(_Symbol, PERIOD_CURRENT, 1);
      dir = (close1 > open1) ? DIR_BUY : DIR_SELL;
   }

   if(dir == DIR_BUY) {
      if(trade.Buy(InitialLot, _Symbol, ask, 0, 0, "INI_B")) {
         g_CenterPrice = NormalizeDouble(ask, _Digits);
         g_PrimaryDir = "BUY";
         g_CurrentLayer = 0;
      }
   } 
   else if(dir == DIR_SELL) {
      if(trade.Sell(InitialLot, _Symbol, bid, 0, 0, "INI_S")) {
         g_CenterPrice = NormalizeDouble(bid, _Digits);
         g_PrimaryDir = "SELL";
         g_CurrentLayer = 0;
      }
   }
}

//+------------------------------------------------------------------+
//| Check and Open Grid logic                                        |
//+------------------------------------------------------------------+
void CheckAndOpenGrid(double ask, double bid)
{
   double gridDistancePrice = GridPips * PIP_VALUE;
   double nextGridPrice = 0.0;
   bool triggerGrid = false;

   if(g_PrimaryDir == "BUY") {
      nextGridPrice = NormalizeDouble(g_CenterPrice - ((g_CurrentLayer + 1) * gridDistancePrice), _Digits);
      if(bid <= nextGridPrice) triggerGrid = true;
   } 
   else if(g_PrimaryDir == "SELL") {
      nextGridPrice = NormalizeDouble(g_CenterPrice + ((g_CurrentLayer + 1) * gridDistancePrice), _Digits);
      if(ask >= nextGridPrice) triggerGrid = true;
   }

   if(triggerGrid) {
      double lotSize = NormalizeDouble(InitialLot * MathPow(LotMultiplier, g_CurrentLayer + 1), 2);
      if(g_PrimaryDir == "BUY") {
         trade.Buy(lotSize, _Symbol, ask, 0, 0, "AVG_B");
         trade.Sell(lotSize, _Symbol, bid, 0, 0, "SCL_S");
      } else {
         trade.Sell(lotSize, _Symbol, bid, 0, 0, "AVG_S");
         trade.Buy(lotSize, _Symbol, ask, 0, 0, "SCL_B");
      }
      g_CurrentLayer++;
   }
}

//+------------------------------------------------------------------+
//| Hidden Take Profit Logic                                         |
//+------------------------------------------------------------------+
void CheckHiddenTPs(double totalFloating, double totalLots)
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double contractSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);

   if(g_CurrentLayer == 0) {
      double trendFollowDiff = TrendFollowTP_Pips * PIP_VALUE;
      if(g_PrimaryDir == "BUY" && bid >= g_CenterPrice + trendFollowDiff) {
         Print("Trend Follow TP Hit for BUY!");
         CloseAllPositions();
         return;
      }
      if(g_PrimaryDir == "SELL" && ask <= g_CenterPrice - trendFollowDiff) {
         Print("Trend Follow TP Hit for SELL!");
         CloseAllPositions();
         return;
      }
   }
   else {
      double basketTargetUSD = (BasketProfitPips * PIP_VALUE) * totalLots * contractSize;
      if(totalFloating >= basketTargetUSD && totalLots > 0) {
         Print("Basket TP Hit! Profit: $", totalFloating);
         CloseAllPositions();
         return;
      }
   }

   double scalpingTPDiff = ScalpingTP_Pips * PIP_VALUE;
   for(int i=PositionsTotal()-1; i>=0; i--) {
      if(pos.SelectByIndex(i) && pos.Magic() == MagicNumber && pos.Symbol() == _Symbol) {
         string comment = pos.Comment();
         double openPrice = pos.PriceOpen();
         ulong ticket = pos.Ticket();
         if(comment == "SCL_B" && bid >= openPrice + scalpingTPDiff) {
            trade.PositionClose(ticket);
            Print("Scalping BUY TP Closed!");
         }
         else if(comment == "SCL_S" && ask <= openPrice - scalpingTPDiff) {
            trade.PositionClose(ticket);
            Print("Scalping SELL TP Closed!");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Close All Magic Positions                                        |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i=PositionsTotal()-1; i>=0; i--) {
      if(pos.SelectByIndex(i)) {
         if(pos.Magic() == MagicNumber && pos.Symbol() == _Symbol) {
            trade.PositionClose(pos.Ticket());
         }
      }
   }
   g_CenterPrice = 0.0;
   g_CurrentLayer = 0;
   g_PrimaryDir = "";
}

//+------------------------------------------------------------------+
//| Recover State on Restart                                         |
//+------------------------------------------------------------------+
void RecoverState()
{
   for(int i=PositionsTotal()-1; i>=0; i--) {
      if(pos.SelectByIndex(i) && pos.Magic() == MagicNumber && pos.Symbol() == _Symbol) {
         string c = pos.Comment();
         if(c == "INI_B") { g_CenterPrice = pos.PriceOpen(); g_PrimaryDir = "BUY"; }
         if(c == "INI_S") { g_CenterPrice = pos.PriceOpen(); g_PrimaryDir = "SELL"; }
      }
   }
   int maxAvg = 0;
   for(int i=PositionsTotal()-1; i>=0; i--) {
      if(pos.SelectByIndex(i) && pos.Magic() == MagicNumber && pos.Symbol() == _Symbol) {
         string c = pos.Comment();
         if(c == "AVG_B" || c == "AVG_S" || c == "SCL_B" || c == "SCL_S") {
            maxAvg++; 
         }
      }
   }
   if(maxAvg > 0 && g_CurrentLayer == 0) g_CurrentLayer = maxAvg / 2;
}

//+------------------------------------------------------------------+
//| Check Time Filter (WITA GMT+8)                                   |
//+------------------------------------------------------------------+
bool CheckTimeFilter(MqlDateTime &dtLocal)
{
   if(!UseTimeFilter) return true;
   int currentMins = dtLocal.hour * 60 + dtLocal.min;
   int startMins = StartHour_GMT8 * 60 + StartMinute;
   int stopMins = StopHour_GMT8 * 60 + StopMinute;
   if (startMins < stopMins) {
      return (currentMins >= startMins && currentMins < stopMins);
   } else {
      return (currentMins >= startMins || currentMins < stopMins);
   }
}

//+------------------------------------------------------------------+
//| Get Today's Closed Profit (Local Time Base)                      |
//+------------------------------------------------------------------+
double GetClosedProfitTodayLocal()
{
   int timeDiff = (int)(TimeLocal() - TimeCurrent());
   MqlDateTime dt; TimeToStruct(TimeLocal(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime localMidnight = StructToTime(dt);
   datetime serverMidnight = localMidnight - timeDiff;
   HistorySelect(serverMidnight, TimeCurrent() + 86400);
   double profit = 0;
   for(int i=0; i<HistoryDealsTotal(); i++) {
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == MagicNumber && 
         HistoryDealGetString(ticket, DEAL_SYMBOL) == _Symbol) {
         profit += HistoryDealGetDouble(ticket, DEAL_PROFIT) +
                   HistoryDealGetDouble(ticket, DEAL_SWAP) +
                   HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      }
   }
   return profit;
}

double totalLots(double b, double s) { return b + s; }

//+------------------------------------------------------------------+
//| Dashboard Functions                                              |
//+------------------------------------------------------------------+
void CreateLabel(string name, int x, int y, int fontSize = 10, color clr = clrWhite)
{
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetString(0, name, OBJPROP_FONT, "Trebuchet MS");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

void CreateDashboard()
{
   CreateLabel("DASH_HEADER", 20, 20, 12, clrGold);
   CreateLabel("DASH_STATUS", 20, 45, 10, clrWhite);
   CreateLabel("DASH_CENTER", 20, 65, 10, clrLightGray);
   CreateLabel("DASH_LAYER",  20, 85, 10, clrLightGray);
   CreateLabel("DASH_BUY",    20, 105, 10, clrDodgerBlue);
   CreateLabel("DASH_SELL",   20, 125, 10, clrOrangeRed);
   CreateLabel("DASH_FLOAT",  20, 145, 10, clrWhite);
   CreateLabel("DASH_DAILY",  20, 165, 10, clrYellow);
   CreateLabel("DASH_NEXT",   20, 185, 10, clrLightGray);
   CreateLabel("DASH_TIME",   20, 205, 10, clrLightGray);
   CreateLabel("DASH_LICENSE",20, 225, 10, clrGreen);
   CreateLabel("DASH_MAGIC",  20, 245, 9, clrGray);
}

void UpdateDashboard(string status, int bCount, double bLot, int sCount, double sLot, double floatUSD, double dailyUSD)
{
   ObjectSetString(0, "DASH_HEADER", OBJPROP_TEXT, "KryonEA + Grid RM™ XAUUSD PRO");
   ObjectSetString(0, "DASH_STATUS", OBJPROP_TEXT, "EA Status        : " + status);
   ObjectSetString(0, "DASH_CENTER", OBJPROP_TEXT, "Center Price   : " + DoubleToString(g_CenterPrice, _Digits));
   ObjectSetString(0, "DASH_LAYER",  OBJPROP_TEXT, "Current Layer  : " + IntegerToString(g_CurrentLayer) + " / " + IntegerToString(MaxGridLayers));
   
   ObjectSetString(0, "DASH_BUY",    OBJPROP_TEXT, "Buy Pos         : " + IntegerToString(bCount) + " (" + DoubleToString(bLot,2) + " lot)");
   ObjectSetString(0, "DASH_SELL",   OBJPROP_TEXT, "Sell Pos         : " + IntegerToString(sCount) + " (" + DoubleToString(sLot,2) + " lot)");
   
   color floatClr = (floatUSD >= 0) ? clrLimeGreen : clrRed;
   ObjectSetInteger(0, "DASH_FLOAT", OBJPROP_COLOR, floatClr);
   ObjectSetString(0, "DASH_FLOAT",  OBJPROP_TEXT, "Total Floating  : " + ((floatUSD>=0)?"+$":"-$") + DoubleToString(MathAbs(floatUSD), 2));
   
   double dailyPct = (MaxDailyProfitUSD > 0) ? (dailyUSD / MaxDailyProfitUSD) * 100.0 : 0;
   ObjectSetString(0, "DASH_DAILY",  OBJPROP_TEXT, "Daily Profit     : $" + DoubleToString(dailyUSD, 2) + " / Max $" + DoubleToString(MaxDailyProfitUSD, 2) + " (" + DoubleToString(dailyPct, 1) + "%)");
   
   string nextGrid = "-";
   if(g_CenterPrice > 0 && g_CurrentLayer < MaxGridLayers) {
      double gridPrice = GridPips * PIP_VALUE;
      if(g_PrimaryDir == "BUY") nextGrid = DoubleToString(g_CenterPrice - ((g_CurrentLayer + 1) * gridPrice), _Digits) + " ↓";
      else if(g_PrimaryDir == "SELL") nextGrid = DoubleToString(g_CenterPrice + ((g_CurrentLayer + 1) * gridPrice), _Digits) + " ↑";
   }
   ObjectSetString(0, "DASH_NEXT",   OBJPROP_TEXT, "Next Grid Lvl   : " + nextGrid);
   
   string timeStr = UseTimeFilter ? StringFormat("%02d:%02d - %02d:%02d (WITA/GMT+8) -> ON", StartHour_GMT8, StartMinute, StopHour_GMT8, StopMinute) : "OFF";
   ObjectSetString(0, "DASH_TIME",   OBJPROP_TEXT, "Time Filter     : " + timeStr);
   
   // Info lisensi
   string licenseInfo = "License: " + (g_LicenseValid ? "VALID" : "INVALID");
   if(g_LicenseValid && g_ExpiryDate > 0) {
      int daysLeft = (int)((g_ExpiryDate - TimeCurrent()) / 86400);
      licenseInfo = StringFormat("License: VALID (expires in %d days)", daysLeft);
   }
   ObjectSetString(0, "DASH_LICENSE",OBJPROP_TEXT, licenseInfo);
   ObjectSetInteger(0, "DASH_LICENSE",OBJPROP_COLOR, g_LicenseValid ? clrLimeGreen : clrRed);
   
   ObjectSetString(0, "DASH_MAGIC",  OBJPROP_TEXT, "Magic: " + IntegerToString(MagicNumber) + " | v1.02");
}
//+------------------------------------------------------------------+