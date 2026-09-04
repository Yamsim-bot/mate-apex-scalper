//+------------------------------------------------------------------+
//|                                           ScalpXAU.mq5           |
//|                  FRVP + Price Action XAUUSD Scalper v3.0          |
//|                                                                    |
//|  Strategy:                                                         |
//|  - Fixed Range Volume Profile zones (POC/VAH/VAL/HVN/LVN)       |
//|  - Price Action patterns at FRVP zones (pin, engulf, combo)      |
//|  - Session gating: Asian range, London breakout, NY sweep         |
//|  - MA50/200 trend bias for direction filter                      |
//|  - ATR-based SL + TP with break-even + trailing                  |
//+------------------------------------------------------------------+
#property copyright "FXRE v3.0"
#property version   "3.20"
#property description "XAUUSD FRVP + Price Action Scalper"
#property description "v3.20: + VP-Pro Mode (Syndicate/Shadow Intel fusion):"
#property description "  Weekly VP POC/VAH/VAL + Hard S/D zones + Order Flow confluence"
#property description "Session-gated entries at Volume Profile zones"
#property strict

//--- INLINE: Trade.mqh ---
//+------------------------------------------------------------------+
//|                                                        Trade.mqh |
//|                             Copyright 2000-2026, MetaQuotes Ltd. |
//|                                                     www.mql5.com |
//+------------------------------------------------------------------+
//--- INLINE: Object.mqh ---
//+------------------------------------------------------------------+
//|                                                       Object.mqh |
//|                             Copyright 2000-2026, MetaQuotes Ltd. |
//|                                                     www.mql5.com |
//+------------------------------------------------------------------+
//--- INLINE: StdLibErr.mqh ---
//+------------------------------------------------------------------+
//|                                                    StdLibErr.mqh |
//|                             Copyright 2000-2026, MetaQuotes Ltd. |
//|                                                     www.mql5.com |
//+------------------------------------------------------------------+
#define ERR_USER_INVALID_HANDLE                            1
#define ERR_USER_INVALID_BUFF_NUM                          2
#define ERR_USER_ITEM_NOT_FOUND                            3
#define ERR_USER_ARRAY_IS_EMPTY                            1000
//+------------------------------------------------------------------+

//--- END INLINE: StdLibErr.mqh ---
//+------------------------------------------------------------------+
//| Class CObject.                                                   |
//| Purpose: Base class for storing elements.                        |
//+------------------------------------------------------------------+
class CObject
  {
private:
   CObject          *m_prev;               // previous item of list
   CObject          *m_next;               // next item of list

public:
                     CObject(void): m_prev(NULL),m_next(NULL)            {                 }
                    ~CObject(void)                                       {                 }
   //--- methods to access protected data
   CObject          *Prev(void)                                    const { return(m_prev); }
   void              Prev(CObject *node)                                 { m_prev=node;    }
   CObject          *Next(void)                                    const { return(m_next); }
   void              Next(CObject *node)                                 { m_next=node;    }
   //--- methods for working with files
   virtual bool      Save(const int file_handle)                         { return(true);   }
   virtual bool      Load(const int file_handle)                         { return(true);   }
   //--- method of identifying the object
   virtual int       Type(void)                                    const { return(0);      }
   //--- method of comparing the objects
   virtual int       Compare(const CObject *node,const int mode=0) const { return(0);      }
  };
//+------------------------------------------------------------------+

//--- END INLINE: Object.mqh ---
//--- INLINE: OrderInfo.mqh ---
//+------------------------------------------------------------------+
//|                                                    OrderInfo.mqh |
//|                             Copyright 2000-2026, MetaQuotes Ltd. |
//|                                                     www.mql5.com |
//+------------------------------------------------------------------+
//--- INLINE: Object.mqh ---
//+------------------------------------------------------------------+
//|                                                       Object.mqh |
//|                             Copyright 2000-2026, MetaQuotes Ltd. |
//|                                                     www.mql5.com |
//+------------------------------------------------------------------+
//--- INLINE: StdLibErr.mqh ---
//+------------------------------------------------------------------+
//|                                                    StdLibErr.mqh |
//|                             Copyright 2000-2026, MetaQuotes Ltd. |
//|                                                     www.mql5.com |
//+------------------------------------------------------------------+
#define ERR_USER_INVALID_HANDLE                            1
#define ERR_USER_INVALID_BUFF_NUM                          2
#define ERR_USER_ITEM_NOT_FOUND                            3
#define ERR_USER_ARRAY_IS_EMPTY                            1000
//+------------------------------------------------------------------+

//--- END INLINE: StdLibErr.mqh ---
//+------------------------------------------------------------------+
//| Class CObject.                                                   |
//| Purpose: Base class for storing elements.                        |
//+------------------------------------------------------------------+
class CObject
  {
private:
   CObject          *m_prev;               // previous item of list
   CObject          *m_next;               // next item of list

public:
                     CObject(void): m_prev(NULL),m_next(NULL)            {                 }
                    ~CObject(void)                                       {                 }
   //--- methods to access protected data
   CObject          *Prev(void)                                    const { return(m_prev); }
   void              Prev(CObject *node)                                 { m_prev=node;    }
   CObject          *Next(void)                                    const { return(m_next); }
   void              Next(CObject *node)                                 { m_next=node;    }
   //--- methods for working with files
   virtual bool      Save(const int file_handle)                         { return(true);   }
   virtual bool      Load(const int file_handle)                         { return(true);   }
   //--- method of identifying the object
   virtual int       Type(void)                                    const { return(0);      }
   //--- method of comparing the objects
   virtual int       Compare(const CObject *node,const int mode=0) const { return(0);      }
  };
//+------------------------------------------------------------------+

//--- END INLINE: Object.mqh ---
//+------------------------------------------------------------------+
//| Class COrderInfo.                                                |
//| Appointment: Class for access to order info.                     |
//|              Derives from class CObject.                         |
//+------------------------------------------------------------------+
class COrderInfo : public CObject
  {
protected:
   ulong             m_ticket;
   ENUM_ORDER_TYPE   m_type;
   ENUM_ORDER_STATE  m_state;
   datetime          m_expiration;
   double            m_volume_curr;
   double            m_price_open;
   double            m_stop_loss;
   double            m_take_profit;

public:
                     COrderInfo(void);
                    ~COrderInfo(void);
   //--- methods of access to protected data
   ulong             Ticket(void) const { return(m_ticket); }
   //--- fast access methods to the integer order propertyes
   datetime          TimeSetup(void) const;
   ulong             TimeSetupMsc(void) const;
   datetime          TimeDone(void) const;
   ulong             TimeDoneMsc(void) const;
   ENUM_ORDER_TYPE   OrderType(void) const;
   string            TypeDescription(void) const;
   ENUM_ORDER_STATE  State(void) const;
   string            StateDescription(void) const;
   datetime          TimeExpiration(void) const;
   ENUM_ORDER_TYPE_FILLING TypeFilling(void) const;
   string            TypeFillingDescription(void) const;
   ENUM_ORDER_TYPE_TIME TypeTime(void) const;
   string            TypeTimeDescription(void) const;
   long              Magic(void) const;
   long              PositionId(void) const;
   long              PositionById(void) const;
   //--- fast access methods to the double order propertyes
   double            VolumeInitial(void) const;
   double            VolumeCurrent(void) const;
   double            PriceOpen(void) const;
   double            StopLoss(void) const;
   double            TakeProfit(void) const;
   double            PriceCurrent(void) const;
   double            PriceStopLimit(void) const;
   //--- fast access methods to the string order propertyes
   string            Symbol(void) const;
   string            Comment(void) const;
   string            ExternalId(void) const;
   //--- access methods to the API MQL5 functions
   bool              InfoInteger(const ENUM_ORDER_PROPERTY_INTEGER prop_id,long &var) const;
   bool              InfoDouble(const ENUM_ORDER_PROPERTY_DOUBLE prop_id,double &var) const;
   bool              InfoString(const ENUM_ORDER_PROPERTY_STRING prop_id,string &var) const;
   //--- info methods
   string            FormatType(string &str,const uint type) const;
   string            FormatStatus(string &str,const uint status) const;
   string            FormatTypeFilling(string &str,const uint type) const;
   string            FormatTypeTime(string &str,const uint type) const;
   string            FormatOrder(string &str) const;
   string            FormatPrice(string &str,const double price_order,const double price_trigger,const uint digits) const;
   //--- method for select order
   bool              Select(void);
   bool              Select(const ulong ticket);
   bool              SelectByIndex(const int index);
   //--- additional methods
   void              StoreState(void);
   bool              CheckState(void);
  };
//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
COrderInfo::COrderInfo(void) : m_ticket(ULONG_MAX),
                               m_type(WRONG_VALUE),
                               m_state(WRONG_VALUE),
                               m_expiration(0),
                               m_volume_curr(0.0),
                               m_price_open(0.0),
                               m_stop_loss(0.0),
                               m_take_profit(0.0)
  {
  }
//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
COrderInfo::~COrderInfo(void)
  {
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TIME_SETUP"                        |
//+------------------------------------------------------------------+
datetime COrderInfo::TimeSetup(void) const
  {
   return((datetime)OrderGetInteger(ORDER_TIME_SETUP));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TIME_SETUP_MSC"                    |
//+------------------------------------------------------------------+
ulong COrderInfo::TimeSetupMsc(void) const
  {
   return(OrderGetInteger(ORDER_TIME_SETUP_MSC));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TIME_DONE"                         |
//+------------------------------------------------------------------+
datetime COrderInfo::TimeDone(void) const
  {
   return((datetime)OrderGetInteger(ORDER_TIME_DONE));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TIME_DONE_MSC"                     |
//+------------------------------------------------------------------+
ulong COrderInfo::TimeDoneMsc(void) const
  {
   return(OrderGetInteger(ORDER_TIME_DONE_MSC));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TYPE"                              |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE COrderInfo::OrderType(void) const
  {
   return((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TYPE" as string                    |
//+------------------------------------------------------------------+
string COrderInfo::TypeDescription(void) const
  {
   string str;
//---
   return(FormatType(str,OrderType()));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_STATE"                             |
//+------------------------------------------------------------------+
ENUM_ORDER_STATE COrderInfo::State(void) const
  {
   return((ENUM_ORDER_STATE)OrderGetInteger(ORDER_STATE));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_STATE" as string                   |
//+------------------------------------------------------------------+
string COrderInfo::StateDescription(void) const
  {
   string str;
//---
   return(FormatStatus(str,State()));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TIME_EXPIRATION"                   |
//+------------------------------------------------------------------+
datetime COrderInfo::TimeExpiration(void) const
  {
   return((datetime)OrderGetInteger(ORDER_TIME_EXPIRATION));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TYPE_FILLING"                      |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING COrderInfo::TypeFilling(void) const
  {
   return((ENUM_ORDER_TYPE_FILLING)OrderGetInteger(ORDER_TYPE_FILLING));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TYPE_FILLING" as string            |
//+------------------------------------------------------------------+
string COrderInfo::TypeFillingDescription(void) const
  {
   string str;
//---
   return(FormatTypeFilling(str,TypeFilling()));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TYPE_TIME"                         |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_TIME COrderInfo::TypeTime(void) const
  {
   return((ENUM_ORDER_TYPE_TIME)OrderGetInteger(ORDER_TYPE_TIME));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TYPE_TIME" as string               |
//+------------------------------------------------------------------+
string COrderInfo::TypeTimeDescription(void) const
  {
   string str;
//---
   return(FormatTypeTime(str,TypeFilling()));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_MAGIC"                             |
//+------------------------------------------------------------------+
long COrderInfo::Magic(void) const
  {
   return(OrderGetInteger(ORDER_MAGIC));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_POSITION_ID"                       |
//+------------------------------------------------------------------+
long COrderInfo::PositionId(void) const
  {
   return(OrderGetInteger(ORDER_POSITION_ID));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_POSITION_BY_ID"                    |
//+------------------------------------------------------------------+
long COrderInfo::PositionById(void) const
  {
   return(OrderGetInteger(ORDER_POSITION_BY_ID));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_VOLUME_INITIAL"                    |
//+------------------------------------------------------------------+
double COrderInfo::VolumeInitial(void) const
  {
   return(OrderGetDouble(ORDER_VOLUME_INITIAL));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_VOLUME_CURRENT"                    |
//+------------------------------------------------------------------+
double COrderInfo::VolumeCurrent(void) const
  {
   return(OrderGetDouble(ORDER_VOLUME_CURRENT));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_PRICE_OPEN"                        |
//+------------------------------------------------------------------+
double COrderInfo::PriceOpen(void) const
  {
   return(OrderGetDouble(ORDER_PRICE_OPEN));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_SL"                                |
//+------------------------------------------------------------------+
double COrderInfo::StopLoss(void) const
  {
   return(OrderGetDouble(ORDER_SL));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TP"                                |
//+------------------------------------------------------------------+
double COrderInfo::TakeProfit(void) const
  {
   return(OrderGetDouble(ORDER_TP));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_PRICE_CURRENT"                     |
//+------------------------------------------------------------------+
double COrderInfo::PriceCurrent(void) const
  {
   return(OrderGetDouble(ORDER_PRICE_CURRENT));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_PRICE_STOPLIMIT"                   |
//+------------------------------------------------------------------+
double COrderInfo::PriceStopLimit(void) const
  {
   return(OrderGetDouble(ORDER_PRICE_STOPLIMIT));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_SYMBOL"                            |
//+------------------------------------------------------------------+
string COrderInfo::Symbol(void) const
  {
   return(OrderGetString(ORDER_SYMBOL));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_COMMENT"                           |
//+------------------------------------------------------------------+
string COrderInfo::Comment(void) const
  {
   return(OrderGetString(ORDER_COMMENT));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_EXTERNAL_ID"                       |
//+------------------------------------------------------------------+
string COrderInfo::ExternalId(void) const
  {
   return(OrderGetString(ORDER_EXTERNAL_ID));
  }
//+------------------------------------------------------------------+
//| Access functions OrderGetInteger(...)                            |
//+------------------------------------------------------------------+
bool COrderInfo::InfoInteger(const ENUM_ORDER_PROPERTY_INTEGER prop_id,long &var) const
  {
   return(OrderGetInteger(prop_id,var));
  }
//+------------------------------------------------------------------+
//| Access functions OrderGetDouble(...)                             |
//+------------------------------------------------------------------+
bool COrderInfo::InfoDouble(const ENUM_ORDER_PROPERTY_DOUBLE prop_id,double &var) const
  {
   return(OrderGetDouble(prop_id,var));
  }
//+------------------------------------------------------------------+
//| Access functions OrderGetString(...)                             |
//+------------------------------------------------------------------+
bool COrderInfo::InfoString(const ENUM_ORDER_PROPERTY_STRING prop_id,string &var) const
  {
   return(OrderGetString(prop_id,var));
  }
//+------------------------------------------------------------------+
//| Converts the order type to text                                  |
//+------------------------------------------------------------------+
string COrderInfo::FormatType(string &str,const uint type) const
  {
//--- see the type
   switch(type)
     {
      case ORDER_TYPE_BUY:
         str="buy";
         break;
      case ORDER_TYPE_SELL:
         str="sell";
         break;
      case ORDER_TYPE_BUY_LIMIT:
         str="buy limit";
         break;
      case ORDER_TYPE_SELL_LIMIT:
         str="sell limit";
         break;
      case ORDER_TYPE_BUY_STOP:
         str="buy stop";
         break;
      case ORDER_TYPE_SELL_STOP:
         str="sell stop";
         break;
      case ORDER_TYPE_BUY_STOP_LIMIT:
         str="buy stop limit";
         break;
      case ORDER_TYPE_SELL_STOP_LIMIT:
         str="sell stop limit";
         break;
      case ORDER_TYPE_CLOSE_BY:
         str="close by";
         break;
      default :
         str="unknown order type "+(string)type;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the order status to text                                |
//+------------------------------------------------------------------+
string COrderInfo::FormatStatus(string &str,const uint status) const
  {
//--- see the type
   switch(status)
     {
      case ORDER_STATE_STARTED:
         str="started";
         break;
      case ORDER_STATE_PLACED:
         str="placed";
         break;
      case ORDER_STATE_CANCELED:
         str="canceled";
         break;
      case ORDER_STATE_PARTIAL:
         str="partial";
         break;
      case ORDER_STATE_FILLED:
         str="filled";
         break;
      case ORDER_STATE_REJECTED:
         str="rejected";
         break;
      case ORDER_STATE_EXPIRED:
         str="expired";
         break;
      case ORDER_STATE_REQUEST_ADD:
         str="request adding";
         break;
      case ORDER_STATE_REQUEST_MODIFY:
         str="request modifying";
         break;
      case ORDER_STATE_REQUEST_CANCEL:
         str="request cancelling";
         break;
      default :
         str="unknown order status "+(string)status;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the order filling type to text                          |
//+------------------------------------------------------------------+
string COrderInfo::FormatTypeFilling(string &str,const uint type) const
  {
//--- see the type
   switch(type)
     {
      case ORDER_FILLING_RETURN:
         str="return remainder";
         break;
      case ORDER_FILLING_IOC:
         str="cancel remainder";
         break;
      case ORDER_FILLING_FOK:
         str="fill or kill";
         break;
      default:
         str="unknown type filling "+(string)type;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the type of order by expiration to text                 |
//+------------------------------------------------------------------+
string COrderInfo::FormatTypeTime(string &str,const uint type) const
  {
//--- see the type
   switch(type)
     {
      case ORDER_TIME_GTC:
         str="gtc";
         break;
      case ORDER_TIME_DAY:
         str="day";
         break;
      case ORDER_TIME_SPECIFIED:
         str="specified";
         break;
      case ORDER_TIME_SPECIFIED_DAY:
         str="specified day";
         break;
      default:
         str="unknown type time "+(string)type;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the order parameters to text                            |
//+------------------------------------------------------------------+
string COrderInfo::FormatOrder(string &str) const
  {
   string type,price;
   long   tmp_long;
//--- set up
   string symbol_name=this.Symbol();
   int    digits=_Digits;
   if(SymbolInfoInteger(symbol_name,SYMBOL_DIGITS,tmp_long))
      digits=(int)tmp_long;
//--- form the order description
   str=StringFormat("#%I64u %s %s %s",
                    Ticket(),
                    FormatType(type,OrderType()),
                    DoubleToString(VolumeInitial(),2),
                    symbol_name);
//--- receive the price of the order
   FormatPrice(price,PriceOpen(),PriceStopLimit(),digits);
//--- if there is price, write it
   if(price!="")
     {
      str+=" at ";
      str+=price;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the order prices to text                                |
//+------------------------------------------------------------------+
string COrderInfo::FormatPrice(string &str,const double price_order,const double price_trigger,const uint digits) const
  {
   string price,trigger;
//--- Is there its trigger price?
   if(price_trigger)
     {
      price  =DoubleToString(price_order,digits);
      trigger=DoubleToString(price_trigger,digits);
      str    =StringFormat("%s (%s)",price,trigger);
     }
   else
      str=DoubleToString(price_order,digits);
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Selecting an order to access                                     |
//+------------------------------------------------------------------+
bool COrderInfo::Select(void)
  {
   return(OrderSelect(m_ticket));
  }
//+------------------------------------------------------------------+
//| Selecting an order to access                                     |
//+------------------------------------------------------------------+
bool COrderInfo::Select(const ulong ticket)
  {
   if(OrderSelect(ticket))
     {
      m_ticket=ticket;
      return(true);
     }
   m_ticket=ULONG_MAX;
//---
   return(false);
  }
//+------------------------------------------------------------------+
//| Select an order by the index                                     |
//+------------------------------------------------------------------+
bool COrderInfo::SelectByIndex(const int index)
  {
   ulong ticket=OrderGetTicket(index);
   if(ticket==0)
     {
      m_ticket=ULONG_MAX;
      return(false);
     }
   m_ticket=ticket;
//---
   return(true);
  }
//+------------------------------------------------------------------+
//| Stored order's current state                                     |
//+------------------------------------------------------------------+
void COrderInfo::StoreState(void)
  {
   m_type       =OrderType();
   m_state      =State();
   m_expiration =TimeExpiration();
   m_volume_curr=VolumeCurrent();
   m_price_open =PriceOpen();
   m_stop_loss  =StopLoss();
   m_take_profit=TakeProfit();
  }
//+------------------------------------------------------------------+
//| Check order change                                               |
//+------------------------------------------------------------------+
bool COrderInfo::CheckState(void)
  {
   if(m_type==OrderType()            &&
      m_state==State()               &&
      m_expiration==TimeExpiration() &&
      m_volume_curr==VolumeCurrent() &&
      m_price_open==PriceOpen()      &&
      m_stop_loss==StopLoss()        &&
      m_take_profit==TakeProfit())
      return(false);
//---
   return(true);
  }
//+------------------------------------------------------------------+

//--- END INLINE: OrderInfo.mqh ---
//--- INLINE: HistoryOrderInfo.mqh ---
//+------------------------------------------------------------------+
//|                                             HistoryOrderInfo.mqh |
//|                             Copyright 2000-2026, MetaQuotes Ltd. |
//|                                                     www.mql5.com |
//+------------------------------------------------------------------+
//--- INLINE: Object.mqh ---
//+------------------------------------------------------------------+
//|                                                       Object.mqh |
//|                             Copyright 2000-2026, MetaQuotes Ltd. |
//|                                                     www.mql5.com |
//+------------------------------------------------------------------+
//--- INLINE: StdLibErr.mqh ---
//+------------------------------------------------------------------+
//|                                                    StdLibErr.mqh |
//|                             Copyright 2000-2026, MetaQuotes Ltd. |
//|                                                     www.mql5.com |
//+------------------------------------------------------------------+
#define ERR_USER_INVALID_HANDLE                            1
#define ERR_USER_INVALID_BUFF_NUM                          2
#define ERR_USER_ITEM_NOT_FOUND                            3
#define ERR_USER_ARRAY_IS_EMPTY                            1000
//+------------------------------------------------------------------+

//--- END INLINE: StdLibErr.mqh ---
//+------------------------------------------------------------------+
//| Class CObject.                                                   |
//| Purpose: Base class for storing elements.                        |
//+------------------------------------------------------------------+
class CObject
  {
private:
   CObject          *m_prev;               // previous item of list
   CObject          *m_next;               // next item of list

public:
                     CObject(void): m_prev(NULL),m_next(NULL)            {                 }
                    ~CObject(void)                                       {                 }
   //--- methods to access protected data
   CObject          *Prev(void)                                    const { return(m_prev); }
   void              Prev(CObject *node)                                 { m_prev=node;    }
   CObject          *Next(void)                                    const { return(m_next); }
   void              Next(CObject *node)                                 { m_next=node;    }
   //--- methods for working with files
   virtual bool      Save(const int file_handle)                         { return(true);   }
   virtual bool      Load(const int file_handle)                         { return(true);   }
   //--- method of identifying the object
   virtual int       Type(void)                                    const { return(0);      }
   //--- method of comparing the objects
   virtual int       Compare(const CObject *node,const int mode=0) const { return(0);      }
  };
//+------------------------------------------------------------------+

//--- END INLINE: Object.mqh ---
//+------------------------------------------------------------------+
//| Class CHistoryOrderInfo.                                         |
//| Appointment: Class for access to history order info.             |
//|              Derives from class CObject.                         |
//+------------------------------------------------------------------+
class CHistoryOrderInfo : public CObject
  {
protected:
   ulong             m_ticket;             // ticket of history order
public:
                     CHistoryOrderInfo(void);
                    ~CHistoryOrderInfo(void);
   //--- methods of access to protected data
   void              Ticket(const ulong ticket) { m_ticket=ticket;  }
   ulong             Ticket(void)         const { return(m_ticket); }
   //--- fast access methods to the integer order propertyes
   datetime          TimeSetup(void) const;
   ulong             TimeSetupMsc(void) const;
   datetime          TimeDone(void) const;
   ulong             TimeDoneMsc(void) const;
   ENUM_ORDER_TYPE   OrderType(void) const;
   string            TypeDescription(void) const;
   ENUM_ORDER_STATE  State(void) const;
   string            StateDescription(void) const;
   datetime          TimeExpiration(void) const;
   ENUM_ORDER_TYPE_FILLING TypeFilling(void) const;
   string            TypeFillingDescription(void) const;
   ENUM_ORDER_TYPE_TIME TypeTime(void) const;
   string            TypeTimeDescription(void) const;
   long              Magic(void) const;
   long              PositionId(void) const;
   long              PositionById(void) const;
   //--- fast access methods to the double order propertyes
   double            VolumeInitial(void) const;
   double            VolumeCurrent(void) const;
   double            PriceOpen(void) const;
   double            StopLoss(void) const;
   double            TakeProfit(void) const;
   double            PriceCurrent(void) const;
   double            PriceStopLimit(void) const;
   //--- fast access methods to the string order propertyes
   string            Symbol(void) const;
   string            Comment(void) const;
   string            ExternalId(void) const;
   //--- access methods to the API MQL5 functions
   bool              InfoInteger(const ENUM_ORDER_PROPERTY_INTEGER prop_id,long &var) const;
   bool              InfoDouble(const ENUM_ORDER_PROPERTY_DOUBLE prop_id,double &var) const;
   bool              InfoString(const ENUM_ORDER_PROPERTY_STRING prop_id,string &var) const;
   //--- info methods
   string            FormatType(string &str,const uint type) const;
   string            FormatStatus(string &str,const uint status) const;
   string            FormatTypeFilling(string &str,const uint type) const;
   string            FormatTypeTime(string &str,const uint type) const;
   string            FormatOrder(string &str) const;
   string            FormatPrice(string &str,const double price_order,const double price_trigger,const uint digits) const;
   //--- method for select history order
   bool              SelectByIndex(const int index);
  };
//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CHistoryOrderInfo::CHistoryOrderInfo(void) : m_ticket(0)
  {
  }
//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CHistoryOrderInfo::~CHistoryOrderInfo(void)
  {
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TIME_SETUP"                        |
//+------------------------------------------------------------------+
datetime CHistoryOrderInfo::TimeSetup(void) const
  {
   return((datetime)HistoryOrderGetInteger(m_ticket,ORDER_TIME_SETUP));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TIME_SETUP_MSC"                    |
//+------------------------------------------------------------------+
ulong CHistoryOrderInfo::TimeSetupMsc(void) const
  {
   return(HistoryOrderGetInteger(m_ticket,ORDER_TIME_SETUP_MSC));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TIME_DONE"                         |
//+------------------------------------------------------------------+
datetime CHistoryOrderInfo::TimeDone(void) const
  {
   return((datetime)HistoryOrderGetInteger(m_ticket,ORDER_TIME_DONE));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TIME_DONE_MSC"                     |
//+------------------------------------------------------------------+
ulong CHistoryOrderInfo::TimeDoneMsc(void) const
  {
   return(HistoryOrderGetInteger(m_ticket,ORDER_TIME_DONE_MSC));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TYPE"                              |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE CHistoryOrderInfo::OrderType(void) const
  {
   return((ENUM_ORDER_TYPE)HistoryOrderGetInteger(m_ticket,ORDER_TYPE));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TYPE" as string                    |
//+------------------------------------------------------------------+
string CHistoryOrderInfo::TypeDescription(void) const
  {
   string str;
//---
   return(FormatType(str,OrderType()));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_STATE"                             |
//+------------------------------------------------------------------+
ENUM_ORDER_STATE CHistoryOrderInfo::State(void) const
  {
   return((ENUM_ORDER_STATE)HistoryOrderGetInteger(m_ticket,ORDER_STATE));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_STATE" as string                   |
//+------------------------------------------------------------------+
string CHistoryOrderInfo::StateDescription(void) const
  {
   string str;
//---
   return(FormatStatus(str,State()));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TIME_EXPIRATION"                   |
//+------------------------------------------------------------------+
datetime CHistoryOrderInfo::TimeExpiration(void) const
  {
   return((datetime)HistoryOrderGetInteger(m_ticket,ORDER_TIME_EXPIRATION));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TYPE_FILLING"                      |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING CHistoryOrderInfo::TypeFilling(void) const
  {
   return((ENUM_ORDER_TYPE_FILLING)HistoryOrderGetInteger(m_ticket,ORDER_TYPE_FILLING));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TYPE_FILLING" as string            |
//+------------------------------------------------------------------+
string CHistoryOrderInfo::TypeFillingDescription(void) const
  {
   string str;
//---
   return(FormatTypeFilling(str,TypeFilling()));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TYPE_TIME"                         |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_TIME CHistoryOrderInfo::TypeTime(void) const
  {
   return((ENUM_ORDER_TYPE_TIME)HistoryOrderGetInteger(m_ticket,ORDER_TYPE_TIME));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TYPE_TIME" as string               |
//+------------------------------------------------------------------+
string CHistoryOrderInfo::TypeTimeDescription(void) const
  {
   string str;
//---
   return(FormatTypeTime(str,TypeTime()));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_EXPERT"                            |
//+------------------------------------------------------------------+
long CHistoryOrderInfo::Magic(void) const
  {
   return(HistoryOrderGetInteger(m_ticket,ORDER_MAGIC));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_POSITION_ID"                       |
//+------------------------------------------------------------------+
long CHistoryOrderInfo::PositionId(void) const
  {
   return(HistoryOrderGetInteger(m_ticket,ORDER_POSITION_ID));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_POSITION_BY_ID"                    |
//+------------------------------------------------------------------+
long CHistoryOrderInfo::PositionById(void) const
  {
   return(HistoryOrderGetInteger(m_ticket,ORDER_POSITION_BY_ID));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_VOLUME_INITIAL"                    |
//+------------------------------------------------------------------+
double CHistoryOrderInfo::VolumeInitial(void) const
  {
   return(HistoryOrderGetDouble(m_ticket,ORDER_VOLUME_INITIAL));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_VOLUME_CURRENT"                    |
//+------------------------------------------------------------------+
double CHistoryOrderInfo::VolumeCurrent(void) const
  {
   return(HistoryOrderGetDouble(m_ticket,ORDER_VOLUME_CURRENT));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_PRICE_OPEN"                        |
//+------------------------------------------------------------------+
double CHistoryOrderInfo::PriceOpen(void) const
  {
   return(HistoryOrderGetDouble(m_ticket,ORDER_PRICE_OPEN));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_SL"                                |
//+------------------------------------------------------------------+
double CHistoryOrderInfo::StopLoss(void) const
  {
   return(HistoryOrderGetDouble(m_ticket,ORDER_SL));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_TP"                                |
//+------------------------------------------------------------------+
double CHistoryOrderInfo::TakeProfit(void) const
  {
   return(HistoryOrderGetDouble(m_ticket,ORDER_TP));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_PRICE_CURRENT"                     |
//+------------------------------------------------------------------+
double CHistoryOrderInfo::PriceCurrent(void) const
  {
   return(HistoryOrderGetDouble(m_ticket,ORDER_PRICE_CURRENT));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_PRICE_STOPLIMIT"                   |
//+------------------------------------------------------------------+
double CHistoryOrderInfo::PriceStopLimit(void) const
  {
   return(HistoryOrderGetDouble(m_ticket,ORDER_PRICE_STOPLIMIT));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_SYMBOL"                            |
//+------------------------------------------------------------------+
string CHistoryOrderInfo::Symbol(void) const
  {
   return(HistoryOrderGetString(m_ticket,ORDER_SYMBOL));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_COMMENT"                           |
//+------------------------------------------------------------------+
string CHistoryOrderInfo::Comment(void) const
  {
   return(HistoryOrderGetString(m_ticket,ORDER_COMMENT));
  }
//+------------------------------------------------------------------+
//| Get the property value "ORDER_EXTERNAL_ID"                       |
//+------------------------------------------------------------------+
string CHistoryOrderInfo::ExternalId(void) const
  {
   return(HistoryOrderGetString(m_ticket,ORDER_EXTERNAL_ID));
  }
//+------------------------------------------------------------------+
//| Access functions OrderGetInteger(...)                            |
//+------------------------------------------------------------------+
bool CHistoryOrderInfo::InfoInteger(const ENUM_ORDER_PROPERTY_INTEGER prop_id,long &var) const
  {
   return(HistoryOrderGetInteger(m_ticket,prop_id,var));
  }
//+------------------------------------------------------------------+
//| Access functions OrderGetDouble(...)                             |
//+------------------------------------------------------------------+
bool CHistoryOrderInfo::InfoDouble(const ENUM_ORDER_PROPERTY_DOUBLE prop_id,double &var) const
  {
   return(HistoryOrderGetDouble(m_ticket,prop_id,var));
  }
//+------------------------------------------------------------------+
//| Access functions OrderGetString(...)                             |
//+------------------------------------------------------------------+
bool CHistoryOrderInfo::InfoString(const ENUM_ORDER_PROPERTY_STRING prop_id,string &var) const
  {
   return(HistoryOrderGetString(m_ticket,prop_id,var));
  }
//+------------------------------------------------------------------+
//| Converts the order type to text                                  |
//+------------------------------------------------------------------+
string CHistoryOrderInfo::FormatType(string &str,const uint type) const
  {
//--- see the type
   switch(type)
     {
      case ORDER_TYPE_BUY:
         str="buy";
         break;
      case ORDER_TYPE_SELL:
         str="sell";
         break;
      case ORDER_TYPE_BUY_LIMIT:
         str="buy limit";
         break;
      case ORDER_TYPE_SELL_LIMIT:
         str="sell limit";
         break;
      case ORDER_TYPE_BUY_STOP:
         str="buy stop";
         break;
      case ORDER_TYPE_SELL_STOP:
         str="sell stop";
         break;
      case ORDER_TYPE_BUY_STOP_LIMIT:
         str="buy stop limit";
         break;
      case ORDER_TYPE_SELL_STOP_LIMIT:
         str="sell stop limit";
         break;
      case ORDER_TYPE_CLOSE_BY:
         str="close by";
         break;
      default:
         str="unknown order type "+(string)type;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the order status to text                                |
//+------------------------------------------------------------------+
string CHistoryOrderInfo::FormatStatus(string &str,const uint status) const
  {
//--- see the type
   switch(status)
     {
      case ORDER_STATE_STARTED:
         str="started";
         break;
      case ORDER_STATE_PLACED:
         str="placed";
         break;
      case ORDER_STATE_CANCELED:
         str="canceled";
         break;
      case ORDER_STATE_PARTIAL:
         str="partial";
         break;
      case ORDER_STATE_FILLED:
         str="filled";
         break;
      case ORDER_STATE_REJECTED:
         str="rejected";
         break;
      case ORDER_STATE_EXPIRED:
         str="expired";
         break;
      default:
         str="unknown order status "+(string)status;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the order filling type to text                          |
//+------------------------------------------------------------------+
string CHistoryOrderInfo::FormatTypeFilling(string &str,const uint type) const
  {
//--- see the type
   switch(type)
     {
      case ORDER_FILLING_RETURN:
         str="return remainder";
         break;
      case ORDER_FILLING_IOC:
         str="cancel remainder";
         break;
      case ORDER_FILLING_FOK:
         str="fill or kill";
         break;
      default:
         str="unknown type filling "+(string)type;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the type of order by expiration to text                 |
//+------------------------------------------------------------------+
string CHistoryOrderInfo::FormatTypeTime(string &str,const uint type) const
  {
//--- see the type
   switch(type)
     {
      case ORDER_TIME_GTC:
         str="gtc";
         break;
      case ORDER_TIME_DAY:
         str="day";
         break;
      case ORDER_TIME_SPECIFIED:
         str="specified";
         break;
      case ORDER_TIME_SPECIFIED_DAY:
         str="specified day";
         break;
      default:
         str="unknown type time "+(string)type;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the order parameters to text                            |
//+------------------------------------------------------------------+
string CHistoryOrderInfo::FormatOrder(string &str) const
  {
   string type,price;
   long   tmp_long;
//--- set up
   string symbol_name=this.Symbol();
   int    digits=_Digits;
   if(SymbolInfoInteger(symbol_name,SYMBOL_DIGITS,tmp_long))
      digits=(int)tmp_long;
//--- form the order description
   str=StringFormat("#%I64u %s %s %s",
                    Ticket(),
                    FormatType(type,OrderType()),
                    DoubleToString(VolumeInitial(),2),
                    symbol_name);
//--- receive the price of the order
   FormatPrice(price,PriceOpen(),PriceStopLimit(),digits);
//--- if there is price, write it
   if(price!="")
     {
      str+=" at ";
      str+=price;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the order prices to text                                |
//+------------------------------------------------------------------+
string CHistoryOrderInfo::FormatPrice(string &str,const double price_order,const double price_trigger,const uint digits) const
  {
   string price,trigger;
//--- Is there its trigger price?
   if(price_trigger)
     {
      price  =DoubleToString(price_order,digits);
      trigger=DoubleToString(price_trigger,digits);
      str    =StringFormat("%s (%s)",price,trigger);
     }
   else
      str=DoubleToString(price_order,digits);
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Select a history order on the index                              |
//+------------------------------------------------------------------+
bool CHistoryOrderInfo::SelectByIndex(const int index)
  {
   ulong ticket=HistoryOrderGetTicket(index);
   if(ticket==0)
      return(false);
   Ticket(ticket);
//---
   return(true);
  }
//+------------------------------------------------------------------+

//--- END INLINE: HistoryOrderInfo.mqh ---
//--- INLINE: PositionInfo.mqh ---
//+------------------------------------------------------------------+
//|                                                 PositionInfo.mqh |
//|                             Copyright 2000-2026, MetaQuotes Ltd. |
//|                                                     www.mql5.com |
//+------------------------------------------------------------------+
//--- INLINE: Object.mqh ---
//+------------------------------------------------------------------+
//|                                                       Object.mqh |
//|                             Copyright 2000-2026, MetaQuotes Ltd. |
//|                                                     www.mql5.com |
//+------------------------------------------------------------------+
//--- INLINE: StdLibErr.mqh ---
//+------------------------------------------------------------------+
//|                                                    StdLibErr.mqh |
//|                             Copyright 2000-2026, MetaQuotes Ltd. |
//|                                                     www.mql5.com |
//+------------------------------------------------------------------+
#define ERR_USER_INVALID_HANDLE                            1
#define ERR_USER_INVALID_BUFF_NUM                          2
#define ERR_USER_ITEM_NOT_FOUND                            3
#define ERR_USER_ARRAY_IS_EMPTY                            1000
//+------------------------------------------------------------------+

//--- END INLINE: StdLibErr.mqh ---
//+------------------------------------------------------------------+
//| Class CObject.                                                   |
//| Purpose: Base class for storing elements.                        |
//+------------------------------------------------------------------+
class CObject
  {
private:
   CObject          *m_prev;               // previous item of list
   CObject          *m_next;               // next item of list

public:
                     CObject(void): m_prev(NULL),m_next(NULL)            {                 }
                    ~CObject(void)                                       {                 }
   //--- methods to access protected data
   CObject          *Prev(void)                                    const { return(m_prev); }
   void              Prev(CObject *node)                                 { m_prev=node;    }
   CObject          *Next(void)                                    const { return(m_next); }
   void              Next(CObject *node)                                 { m_next=node;    }
   //--- methods for working with files
   virtual bool      Save(const int file_handle)                         { return(true);   }
   virtual bool      Load(const int file_handle)                         { return(true);   }
   //--- method of identifying the object
   virtual int       Type(void)                                    const { return(0);      }
   //--- method of comparing the objects
   virtual int       Compare(const CObject *node,const int mode=0) const { return(0);      }
  };
//+------------------------------------------------------------------+

//--- END INLINE: Object.mqh ---
//+------------------------------------------------------------------+
//| Class CPositionInfo.                                             |
//| Appointment: Class for access to position info.                  |
//|              Derives from class CObject.                         |
//+------------------------------------------------------------------+
class CPositionInfo : public CObject
  {
protected:
   ENUM_POSITION_TYPE m_type;
   double            m_volume;
   double            m_price;
   double            m_stop_loss;
   double            m_take_profit;

public:
                     CPositionInfo(void);
                    ~CPositionInfo(void);
   //--- fast access methods to the integer position propertyes
   ulong             Ticket(void) const;
   datetime          Time(void) const;
   ulong             TimeMsc(void) const;
   datetime          TimeUpdate(void) const;
   ulong             TimeUpdateMsc(void) const;
   ENUM_POSITION_TYPE PositionType(void) const;
   string            TypeDescription(void) const;
   long              Magic(void) const;
   long              Identifier(void) const;
   //--- fast access methods to the double position propertyes
   double            Volume(void) const;
   double            PriceOpen(void) const;
   double            StopLoss(void) const;
   double            TakeProfit(void) const;
   double            PriceCurrent(void) const;
   double            Commission(void) const;
   double            Swap(void) const;
   double            Profit(void) const;
   //--- fast access methods to the string position propertyes
   string            Symbol(void) const;
   string            Comment(void) const;
   //--- access methods to the API MQL5 functions
   bool              InfoInteger(const ENUM_POSITION_PROPERTY_INTEGER prop_id,long &var) const;
   bool              InfoDouble(const ENUM_POSITION_PROPERTY_DOUBLE prop_id,double &var) const;
   bool              InfoString(const ENUM_POSITION_PROPERTY_STRING prop_id,string &var) const;
   //--- info methods
   string            FormatType(string &str,const uint type) const;
   string            FormatPosition(string &str) const;
   //--- methods for select position
   bool              Select(const string symbol);
   bool              SelectByMagic(const string symbol,const ulong magic);
   bool              SelectByTicket(const ulong ticket);
   bool              SelectByIndex(const int index);
   //---
   void              StoreState(void);
   bool              CheckState(void);
  };
//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CPositionInfo::CPositionInfo(void) : m_type(WRONG_VALUE),
                                     m_volume(0.0),
                                     m_price(0.0),
                                     m_stop_loss(0.0),
                                     m_take_profit(0.0)
  {
  }
//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CPositionInfo::~CPositionInfo(void)
  {
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_TICKET"                         |
//+------------------------------------------------------------------+
ulong CPositionInfo::Ticket(void) const
  {
   return((ulong)PositionGetInteger(POSITION_TICKET));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_TIME"                           |
//+------------------------------------------------------------------+
datetime CPositionInfo::Time(void) const
  {
   return((datetime)PositionGetInteger(POSITION_TIME));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_TIME_MSC"                       |
//+------------------------------------------------------------------+
ulong CPositionInfo::TimeMsc(void) const
  {
   return((ulong)PositionGetInteger(POSITION_TIME_MSC));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_TIME_UPDATE"                    |
//+------------------------------------------------------------------+
datetime CPositionInfo::TimeUpdate(void) const
  {
   return((datetime)PositionGetInteger(POSITION_TIME_UPDATE));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_TIME_UPDATE_MSC"                |
//+------------------------------------------------------------------+
ulong CPositionInfo::TimeUpdateMsc(void) const
  {
   return((ulong)PositionGetInteger(POSITION_TIME_UPDATE_MSC));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_TYPE"                           |
//+------------------------------------------------------------------+
ENUM_POSITION_TYPE CPositionInfo::PositionType(void) const
  {
   return((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_TYPE" as string                 |
//+------------------------------------------------------------------+
string CPositionInfo::TypeDescription(void) const
  {
   string str;
//---
   return(FormatType(str,PositionType()));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_MAGIC"                          |
//+------------------------------------------------------------------+
long CPositionInfo::Magic(void) const
  {
   return(PositionGetInteger(POSITION_MAGIC));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_IDENTIFIER"                     |
//+------------------------------------------------------------------+
long CPositionInfo::Identifier(void) const
  {
   return(PositionGetInteger(POSITION_IDENTIFIER));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_VOLUME"                         |
//+------------------------------------------------------------------+
double CPositionInfo::Volume(void) const
  {
   return(PositionGetDouble(POSITION_VOLUME));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_PRICE_OPEN"                     |
//+------------------------------------------------------------------+
double CPositionInfo::PriceOpen(void) const
  {
   return(PositionGetDouble(POSITION_PRICE_OPEN));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_SL"                             |
//+------------------------------------------------------------------+
double CPositionInfo::StopLoss(void) const
  {
   return(PositionGetDouble(POSITION_SL));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_TP"                             |
//+------------------------------------------------------------------+
double CPositionInfo::TakeProfit(void) const
  {
   return(PositionGetDouble(POSITION_TP));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_PRICE_CURRENT"                  |
//+------------------------------------------------------------------+
double CPositionInfo::PriceCurrent(void) const
  {
   return(PositionGetDouble(POSITION_PRICE_CURRENT));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_COMMISSION"                     |
//+------------------------------------------------------------------+
double CPositionInfo::Commission(void) const
  {
//--- property POSITION_COMMISSION is deprecated
   SetUserError(ERR_FUNCTION_NOT_ALLOWED);
   return(0);
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_SWAP"                           |
//+------------------------------------------------------------------+
double CPositionInfo::Swap(void) const
  {
   return(PositionGetDouble(POSITION_SWAP));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_PROFIT"                         |
//+------------------------------------------------------------------+
double CPositionInfo::Profit(void) const
  {
   return(PositionGetDouble(POSITION_PROFIT));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_SYMBOL"                         |
//+------------------------------------------------------------------+
string CPositionInfo::Symbol(void) const
  {
   return(PositionGetString(POSITION_SYMBOL));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_COMMENT"                        |
//+------------------------------------------------------------------+
string CPositionInfo::Comment(void) const
  {
   return(PositionGetString(POSITION_COMMENT));
  }
//+------------------------------------------------------------------+
//| Access functions PositionGetInteger(...)                         |
//+------------------------------------------------------------------+
bool CPositionInfo::InfoInteger(const ENUM_POSITION_PROPERTY_INTEGER prop_id,long &var) const
  {
   return(PositionGetInteger(prop_id,var));
  }
//+------------------------------------------------------------------+
//| Access functions PositionGetDouble(...)                          |
//+------------------------------------------------------------------+
bool CPositionInfo::InfoDouble(const ENUM_POSITION_PROPERTY_DOUBLE prop_id,double &var) const
  {
   return(PositionGetDouble(prop_id,var));
  }
//+------------------------------------------------------------------+
//| Access functions PositionGetString(...)                          |
//+------------------------------------------------------------------+
bool CPositionInfo::InfoString(const ENUM_POSITION_PROPERTY_STRING prop_id,string &var) const
  {
   return(PositionGetString(prop_id,var));
  }
//+------------------------------------------------------------------+
//| Converts the position type to text                               |
//+------------------------------------------------------------------+
string CPositionInfo::FormatType(string &str,const uint type) const
  {
//--- see the type
   switch(type)
     {
      case POSITION_TYPE_BUY:
         str="buy";
         break;
      case POSITION_TYPE_SELL:
         str="sell";
         break;
      default:
         str="unknown position type "+(string)type;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the position parameters to text                         |
//+------------------------------------------------------------------+
string CPositionInfo::FormatPosition(string &str) const
  {
   string tmp,type;
   long   tmp_long;
   ENUM_ACCOUNT_MARGIN_MODE margin_mode=(ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
//--- set up
   string symbol_name=this.Symbol();
   int    digits=_Digits;
   if(SymbolInfoInteger(symbol_name,SYMBOL_DIGITS,tmp_long))
      digits=(int)tmp_long;
//--- form the position description
   if(margin_mode==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      str=StringFormat("#%I64u %s %s %s %s",
                       Ticket(),
                       FormatType(type,PositionType()),
                       DoubleToString(Volume(),2),
                       symbol_name,
                       DoubleToString(PriceOpen(),digits+3));
   else
      str=StringFormat("%s %s %s %s",
                       FormatType(type,PositionType()),
                       DoubleToString(Volume(),2),
                       symbol_name,
                       DoubleToString(PriceOpen(),digits+3));
//--- add stops if there are any
   double sl=StopLoss();
   double tp=TakeProfit();
   if(sl!=0.0)
     {
      tmp=StringFormat(" sl: %s",DoubleToString(sl,digits));
      str+=tmp;
     }
   if(tp!=0.0)
     {
      tmp=StringFormat(" tp: %s",DoubleToString(tp,digits));
      str+=tmp;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Access functions PositionSelect(...)                             |
//+------------------------------------------------------------------+
bool CPositionInfo::Select(const string symbol)
  {
   return(PositionSelect(symbol));
  }
//+------------------------------------------------------------------+
//| Access functions PositionSelect(...)                             |
//+------------------------------------------------------------------+
bool CPositionInfo::SelectByMagic(const string symbol,const ulong magic)
  {
   bool res=false;
   uint total=PositionsTotal();
//---
   for(uint i=0; i<total; i++)
     {
      string position_symbol=PositionGetSymbol(i);
      if(position_symbol==symbol && magic==PositionGetInteger(POSITION_MAGIC))
        {
         res=true;
         break;
        }
     }
//---
   return(res);
  }
//+------------------------------------------------------------------+
//| Access functions PositionSelectByTicket(...)                     |
//+------------------------------------------------------------------+
bool CPositionInfo::SelectByTicket(const ulong ticket)
  {
   return(PositionSelectByTicket(ticket));
  }
//+------------------------------------------------------------------+
//| Select a position on the index                                   |
//+------------------------------------------------------------------+
bool CPositionInfo::SelectByIndex(const int index)
  {
   ulong ticket=PositionGetTicket(index);
   return(ticket>0);
  }
//+------------------------------------------------------------------+
//| Stored position's current state                                  |
//+------------------------------------------------------------------+
void CPositionInfo::StoreState(void)
  {
   m_type       =PositionType();
   m_volume     =Volume();
   m_price      =PriceOpen();
   m_stop_loss  =StopLoss();
   m_take_profit=TakeProfit();
  }
//+------------------------------------------------------------------+
//| Check position change                                            |
//+------------------------------------------------------------------+
bool CPositionInfo::CheckState(void)
  {
   if(m_type==PositionType()  &&
      m_volume==Volume()      &&
      m_price==PriceOpen()    &&
      m_stop_loss==StopLoss() &&
      m_take_profit==TakeProfit())
      return(false);
//---
   return(true);
  }
//+------------------------------------------------------------------+

//--- END INLINE: PositionInfo.mqh ---
//--- INLINE: DealInfo.mqh ---
//+------------------------------------------------------------------+
//|                                                     DealInfo.mqh |
//|                             Copyright 2000-2026, MetaQuotes Ltd. |
//|                                                     www.mql5.com |
//+------------------------------------------------------------------+
//--- INLINE: Object.mqh ---
//+------------------------------------------------------------------+
//|                                                       Object.mqh |
//|                             Copyright 2000-2026, MetaQuotes Ltd. |
//|                                                     www.mql5.com |
//+------------------------------------------------------------------+
//--- INLINE: StdLibErr.mqh ---
//+------------------------------------------------------------------+
//|                                                    StdLibErr.mqh |
//|                             Copyright 2000-2026, MetaQuotes Ltd. |
//|                                                     www.mql5.com |
//+------------------------------------------------------------------+
#define ERR_USER_INVALID_HANDLE                            1
#define ERR_USER_INVALID_BUFF_NUM                          2
#define ERR_USER_ITEM_NOT_FOUND                            3
#define ERR_USER_ARRAY_IS_EMPTY                            1000
//+------------------------------------------------------------------+

//--- END INLINE: StdLibErr.mqh ---
//+------------------------------------------------------------------+
//| Class CObject.                                                   |
//| Purpose: Base class for storing elements.                        |
//+------------------------------------------------------------------+
class CObject
  {
private:
   CObject          *m_prev;               // previous item of list
   CObject          *m_next;               // next item of list

public:
                     CObject(void): m_prev(NULL),m_next(NULL)            {                 }
                    ~CObject(void)                                       {                 }
   //--- methods to access protected data
   CObject          *Prev(void)                                    const { return(m_prev); }
   void              Prev(CObject *node)                                 { m_prev=node;    }
   CObject          *Next(void)                                    const { return(m_next); }
   void              Next(CObject *node)                                 { m_next=node;    }
   //--- methods for working with files
   virtual bool      Save(const int file_handle)                         { return(true);   }
   virtual bool      Load(const int file_handle)                         { return(true);   }
   //--- method of identifying the object
   virtual int       Type(void)                                    const { return(0);      }
   //--- method of comparing the objects
   virtual int       Compare(const CObject *node,const int mode=0) const { return(0);      }
  };
//+------------------------------------------------------------------+

//--- END INLINE: Object.mqh ---
//+------------------------------------------------------------------+
//| Class CDealInfo.                                                 |
//| Appointment: Class for access to history deal info.              |
//|              Derives from class CObject.                         |
//+------------------------------------------------------------------+
class CDealInfo : public CObject
  {
protected:
   ulong             m_ticket;             // ticket of history order

public:
                     CDealInfo(void);
                    ~CDealInfo(void);
   //--- methods of access to protected data
   void              Ticket(const ulong ticket)   { m_ticket=ticket;  }
   ulong             Ticket(void)           const { return(m_ticket); }
   //--- fast access methods to the integer position propertyes
   long              Order(void) const;
   datetime          Time(void) const;
   ulong             TimeMsc(void) const;
   ENUM_DEAL_TYPE    DealType(void) const;
   string            TypeDescription(void) const;
   ENUM_DEAL_ENTRY   Entry(void) const;
   string            EntryDescription(void) const;
   long              Magic(void) const;
   long              PositionId(void) const;
   //--- fast access methods to the double position propertyes
   double            Volume(void) const;
   double            Price(void) const;
   double            Commission(void) const;
   double            Swap(void) const;
   double            Profit(void) const;
   //--- fast access methods to the string position propertyes
   string            Symbol(void) const;
   string            Comment(void) const;
   string            ExternalId(void) const;
   //--- access methods to the API MQL5 functions
   bool              InfoInteger(ENUM_DEAL_PROPERTY_INTEGER prop_id,long &var) const;
   bool              InfoDouble(ENUM_DEAL_PROPERTY_DOUBLE prop_id,double &var) const;
   bool              InfoString(ENUM_DEAL_PROPERTY_STRING prop_id,string &var) const;
   //--- info methods
   string            FormatAction(string &str,const uint action) const;
   string            FormatEntry(string &str,const uint entry) const;
   string            FormatDeal(string &str) const;
   //--- method for select deal
   bool              SelectByIndex(const int index);
  };
//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CDealInfo::CDealInfo(void)
  {
  }
//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CDealInfo::~CDealInfo(void)
  {
  }
//+------------------------------------------------------------------+
//| Get the property value "DEAL_ORDER"                              |
//+------------------------------------------------------------------+
long CDealInfo::Order(void) const
  {
   return(HistoryDealGetInteger(m_ticket,DEAL_ORDER));
  }
//+------------------------------------------------------------------+
//| Get the property value "DEAL_TIME"                               |
//+------------------------------------------------------------------+
datetime CDealInfo::Time(void) const
  {
   return((datetime)HistoryDealGetInteger(m_ticket,DEAL_TIME));
  }
//+------------------------------------------------------------------+
//| Get the property value "DEAL_TIME_MSC"                           |
//+------------------------------------------------------------------+
ulong CDealInfo::TimeMsc(void) const
  {
   return(HistoryDealGetInteger(m_ticket,DEAL_TIME_MSC));
  }
//+------------------------------------------------------------------+
//| Get the property value "DEAL_TYPE"                               |
//+------------------------------------------------------------------+
ENUM_DEAL_TYPE CDealInfo::DealType(void) const
  {
   return((ENUM_DEAL_TYPE)HistoryDealGetInteger(m_ticket,DEAL_TYPE));
  }
//+------------------------------------------------------------------+
//| Get the property value "DEAL_TYPE" as string                     |
//+------------------------------------------------------------------+
string CDealInfo::TypeDescription(void) const
  {
   string str;
//---
   switch(DealType())
     {
      case DEAL_TYPE_BUY:
         str="Buy type";
         break;
      case DEAL_TYPE_SELL:
         str="Sell type";
         break;
      case DEAL_TYPE_BALANCE:
         str="Balance type";
         break;
      case DEAL_TYPE_CREDIT:
         str="Credit type";
         break;
      case DEAL_TYPE_CHARGE:
         str="Charge type";
         break;
      case DEAL_TYPE_CORRECTION:
         str="Correction type";
         break;
      case DEAL_TYPE_BONUS:
         str="Bonus type";
         break;
      case DEAL_TYPE_COMMISSION:
         str="Commission type";
         break;
      case DEAL_TYPE_COMMISSION_DAILY:
         str="Daily Commission type";
         break;
      case DEAL_TYPE_COMMISSION_MONTHLY:
         str="Monthly Commission type";
         break;
      case DEAL_TYPE_COMMISSION_AGENT_DAILY:
         str="Daily Agent Commission type";
         break;
      case DEAL_TYPE_COMMISSION_AGENT_MONTHLY:
         str="Monthly Agent Commission type";
         break;
      case DEAL_TYPE_INTEREST:
         str="Interest Rate type";
         break;
      case DEAL_TYPE_BUY_CANCELED:
         str="Canceled Buy type";
         break;
      case DEAL_TYPE_SELL_CANCELED:
         str="Canceled Sell type";
         break;
      default:
         str="Unknown type";
     }
//---
   return(str);
  }
//+------------------------------------------------------------------+
//| Get the property value "DEAL_ENTRY"                              |
//+------------------------------------------------------------------+
ENUM_DEAL_ENTRY CDealInfo::Entry(void) const
  {
   return((ENUM_DEAL_ENTRY)HistoryDealGetInteger(m_ticket,DEAL_ENTRY));
  }
//+------------------------------------------------------------------+
//| Get the property value "DEAL_ENTRY" as string                    |
//+------------------------------------------------------------------+
string CDealInfo::EntryDescription(void) const
  {
   string str;
//---
   switch(CDealInfo::Entry())
     {
      case DEAL_ENTRY_IN:
         str="In entry";
         break;
      case DEAL_ENTRY_OUT:
         str="Out entry";
         break;
      case DEAL_ENTRY_INOUT:
         str="InOut entry";
         break;
      case DEAL_ENTRY_STATE:
         str="Status record";
         break;
      case DEAL_ENTRY_OUT_BY:
         str="Out By entry";
         break;
      default:
         str="Unknown entry";
     }
//---
   return(str);
  }
//+------------------------------------------------------------------+
//| Get the property value "DEAL_MAGIC"                              |
//+------------------------------------------------------------------+
long CDealInfo::Magic(void) const
  {
   return(HistoryDealGetInteger(m_ticket,DEAL_MAGIC));
  }
//+------------------------------------------------------------------+
//| Get the property value "DEAL_POSITION_ID"                        |
//+------------------------------------------------------------------+
long CDealInfo::PositionId(void) const
  {
   return(HistoryDealGetInteger(m_ticket,DEAL_POSITION_ID));
  }
//+------------------------------------------------------------------+
//| Get the property value "DEAL_VOLUME"                             |
//+------------------------------------------------------------------+
double CDealInfo::Volume(void) const
  {
   return(HistoryDealGetDouble(m_ticket,DEAL_VOLUME));
  }
//+------------------------------------------------------------------+
//| Get the property value "DEAL_PRICE_OPEN"                         |
//+------------------------------------------------------------------+
double CDealInfo::Price(void) const
  {
   return(HistoryDealGetDouble(m_ticket,DEAL_PRICE));
  }
//+------------------------------------------------------------------+
//| Get the property value "DEAL_COMMISSION"                         |
//+------------------------------------------------------------------+
double CDealInfo::Commission(void) const
  {
   return(HistoryDealGetDouble(m_ticket,DEAL_COMMISSION));
  }
//+------------------------------------------------------------------+
//| Get the property value "DEAL_SWAP"                               |
//+------------------------------------------------------------------+
double CDealInfo::Swap(void) const
  {
   return(HistoryDealGetDouble(m_ticket,DEAL_SWAP));
  }
//+------------------------------------------------------------------+
//| Get the property value "DEAL_PROFIT"                             |
//+------------------------------------------------------------------+
double CDealInfo::Profit(void) const
  {
   return(HistoryDealGetDouble(m_ticket,DEAL_PROFIT));
  }
//+------------------------------------------------------------------+
//| Get the property value "DEAL_SYMBOL"                             |
//+------------------------------------------------------------------+
string CDealInfo::Symbol(void) const
  {
   return(HistoryDealGetString(m_ticket,DEAL_SYMBOL));
  }
//+------------------------------------------------------------------+
//| Get the property value "DEAL_COMMENT"                            |
//+------------------------------------------------------------------+
string CDealInfo::Comment(void) const
  {
   return(HistoryDealGetString(m_ticket,DEAL_COMMENT));
  }
//+------------------------------------------------------------------+
//| Get the property value "DEAL_EXTERNAL_ID"                        |
//+------------------------------------------------------------------+
string CDealInfo::ExternalId(void) const
  {
   return(HistoryDealGetString(m_ticket,DEAL_EXTERNAL_ID));
  }
//+------------------------------------------------------------------+
//| Access functions HistoryDealGetInteger(...)                      |
//+------------------------------------------------------------------+
bool CDealInfo::InfoInteger(ENUM_DEAL_PROPERTY_INTEGER prop_id,long &var) const
  {
   return(HistoryDealGetInteger(m_ticket,prop_id,var));
  }
//+------------------------------------------------------------------+
//| Access functions HistoryDealGetDouble(...)                       |
//+------------------------------------------------------------------+
bool CDealInfo::InfoDouble(ENUM_DEAL_PROPERTY_DOUBLE prop_id,double &var) const
  {
   return(HistoryDealGetDouble(m_ticket,prop_id,var));
  }
//+------------------------------------------------------------------+
//| Access functions HistoryDealGetString(...)                       |
//+------------------------------------------------------------------+
bool CDealInfo::InfoString(ENUM_DEAL_PROPERTY_STRING prop_id,string &var) const
  {
   return(HistoryDealGetString(m_ticket,prop_id,var));
  }
//+------------------------------------------------------------------+
//| Converths the type of a  deal to text                            |
//+------------------------------------------------------------------+
string CDealInfo::FormatAction(string &str,const uint action) const
  {
//--- see the type
   switch(action)
     {
      case DEAL_TYPE_BUY:
         str="buy";
         break;
      case DEAL_TYPE_SELL:
         str="sell";
         break;
      case DEAL_TYPE_BALANCE:
         str="balance";
         break;
      case DEAL_TYPE_CREDIT:
         str="credit";
         break;
      case DEAL_TYPE_CHARGE:
         str="charge";
         break;
      case DEAL_TYPE_CORRECTION:
         str="correction";
         break;
      case DEAL_TYPE_BONUS:
         str="bonus";
         break;
      case DEAL_TYPE_COMMISSION:
         str="commission";
         break;
      case DEAL_TYPE_COMMISSION_DAILY:
         str="daily commission";
         break;
      case DEAL_TYPE_COMMISSION_MONTHLY:
         str="monthly commission";
         break;
      case DEAL_TYPE_COMMISSION_AGENT_DAILY:
         str="daily agent commission";
         break;
      case DEAL_TYPE_COMMISSION_AGENT_MONTHLY:
         str="monthly agent commission";
         break;
      case DEAL_TYPE_INTEREST:
         str="interest rate";
         break;
      case DEAL_TYPE_BUY_CANCELED:
         str="canceled buy";
         break;
      case DEAL_TYPE_SELL_CANCELED:
         str="canceled sell";
         break;
      default:
         str="unknown deal type "+(string)action;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the deal direction to text                              |
//+------------------------------------------------------------------+
string CDealInfo::FormatEntry(string &str,const uint entry) const
  {
//--- see the type
   switch(entry)
     {
      case DEAL_ENTRY_IN:
         str="in";
         break;
      case DEAL_ENTRY_OUT:
         str="out";
         break;
      case DEAL_ENTRY_INOUT:
         str="in/out";
         break;
      case DEAL_ENTRY_OUT_BY:
         str="out by";
         break;
      default:
         str="unknown deal entry "+(string)entry;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the deal parameters to text                             |
//+------------------------------------------------------------------+
string CDealInfo::FormatDeal(string &str) const
  {
   string type;
   long   tmp_long;
//--- set up
   string symbol_name=this.Symbol();
   int    digits=_Digits;
   if(SymbolInfoInteger(symbol_name,SYMBOL_DIGITS,tmp_long))
      digits=(int)tmp_long;
//--- form the description of the deal
   switch(DealType())
     {
      //--- Buy-Sell
      case DEAL_TYPE_BUY:
      case DEAL_TYPE_SELL:
         str=StringFormat("#%I64u %s %s %s at %s",
                          Ticket(),
                          FormatAction(type,DealType()),
                          DoubleToString(Volume(),2),
                          symbol_name,
                          DoubleToString(Price(),digits));
         break;

      //--- balance operations
      case DEAL_TYPE_BALANCE:
      case DEAL_TYPE_CREDIT:
      case DEAL_TYPE_CHARGE:
      case DEAL_TYPE_CORRECTION:
      case DEAL_TYPE_BONUS:
      case DEAL_TYPE_COMMISSION:
      case DEAL_TYPE_COMMISSION_DAILY:
      case DEAL_TYPE_COMMISSION_MONTHLY:
      case DEAL_TYPE_COMMISSION_AGENT_DAILY:
      case DEAL_TYPE_COMMISSION_AGENT_MONTHLY:
      case DEAL_TYPE_INTEREST:
         str=StringFormat("#%I64u %s %s [%s]",
                          Ticket(),
                          FormatAction(type,DealType()),
                          DoubleToString(Profit(),2),
                          this.Comment());
         break;

      default:
         str="unknown deal type "+(string)DealType();
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Select a deal on the index                                       |
//+------------------------------------------------------------------+
bool CDealInfo::SelectByIndex(const int index)
  {
   ulong ticket=HistoryDealGetTicket(index);
   if(ticket==0)
      return(false);
   Ticket(ticket);
//---
   return(true);
  }
//+------------------------------------------------------------------+

//--- END INLINE: DealInfo.mqh ---
//+------------------------------------------------------------------+
//| enumerations                                                     |
//+------------------------------------------------------------------+
enum ENUM_LOG_LEVELS
  {
   LOG_LEVEL_NO    =0,
   LOG_LEVEL_ERRORS=1,
   LOG_LEVEL_ALL   =2
  };
//+------------------------------------------------------------------+
//| Class CTrade.                                                    |
//| Appointment: Class trade operations.                             |
//|              Derives from class CObject.                         |
//+------------------------------------------------------------------+
class CTrade : public CObject
  {
protected:
   MqlTradeRequest   m_request;              // request data
   MqlTradeResult    m_result;               // result data
   MqlTradeCheckResult m_check_result;       // result check data
   bool              m_async_mode;           // trade mode
   ulong             m_magic;                // expert magic number
   ulong             m_deviation;            // deviation default
   ENUM_ORDER_TYPE_FILLING m_type_filling;
   ENUM_ACCOUNT_MARGIN_MODE m_margin_mode;
   //---
   ENUM_LOG_LEVELS   m_log_level;

public:
                     CTrade(void);
                    ~CTrade(void);
   //--- methods of access to protected data
   void              LogLevel(const ENUM_LOG_LEVELS log_level) { m_log_level=log_level; }
   void              Request(MqlTradeRequest &request) const;
   ENUM_TRADE_REQUEST_ACTIONS RequestAction(void)   const { return(m_request.action);       }
   string            RequestActionDescription(void) const;
   ulong             RequestMagic(void)             const { return(m_request.magic);        }
   ulong             RequestOrder(void)             const { return(m_request.order);        }
   ulong             RequestPosition(void)          const { return(m_request.position);     }
   ulong             RequestPositionBy(void)        const { return(m_request.position_by);  }
   string            RequestSymbol(void)            const { return(m_request.symbol);       }
   double            RequestVolume(void)            const { return(m_request.volume);       }
   double            RequestPrice(void)             const { return(m_request.price);        }
   double            RequestStopLimit(void)         const { return(m_request.stoplimit);    }
   double            RequestSL(void)                const { return(m_request.sl);           }
   double            RequestTP(void)                const { return(m_request.tp);           }
   ulong             RequestDeviation(void)         const { return(m_request.deviation);    }
   ENUM_ORDER_TYPE   RequestType(void)              const { return(m_request.type);         }
   string            RequestTypeDescription(void) const;
   ENUM_ORDER_TYPE_FILLING RequestTypeFilling(void) const { return(m_request.type_filling); }
   string            RequestTypeFillingDescription(void) const;
   ENUM_ORDER_TYPE_TIME RequestTypeTime(void)       const { return(m_request.type_time);    }
   string            RequestTypeTimeDescription(void) const;
   datetime          RequestExpiration(void)        const { return(m_request.expiration);   }
   string            RequestComment(void)           const { return(m_request.comment);      }
   //---
   void              Result(MqlTradeResult &result) const;
   uint              ResultRetcode(void)         const { return(m_result.retcode);          }
   string            ResultRetcodeDescription(void) const;
   int               ResultRetcodeExternal(void) const { return(m_result.retcode_external); }
   ulong             ResultDeal(void)            const { return(m_result.deal);             }
   ulong             ResultOrder(void)           const { return(m_result.order);            }
   double            ResultVolume(void)          const { return(m_result.volume);           }
   double            ResultPrice(void)           const { return(m_result.price);            }
   double            ResultBid(void)             const { return(m_result.bid);              }
   double            ResultAsk(void)             const { return(m_result.ask);              }
   string            ResultComment(void)         const { return(m_result.comment);          }
   //---
   void              CheckResult(MqlTradeCheckResult &check_result) const;
   uint              CheckResultRetcode(void)     const { return(m_check_result.retcode);      }
   string            CheckResultRetcodeDescription(void) const;
   double            CheckResultBalance(void)     const { return(m_check_result.balance);      }
   double            CheckResultEquity(void)      const { return(m_check_result.equity);       }
   double            CheckResultProfit(void)      const { return(m_check_result.profit);       }
   double            CheckResultMargin(void)      const { return(m_check_result.margin);       }
   double            CheckResultMarginFree(void)  const { return(m_check_result.margin_free);  }
   double            CheckResultMarginLevel(void) const { return(m_check_result.margin_level); }
   string            CheckResultComment(void)     const { return(m_check_result.comment);      }
   //--- trade methods
   void              SetAsyncMode(const bool mode)               { m_async_mode=mode;                }
   void              SetExpertMagicNumber(const ulong magic)     { m_magic=magic;                    }
   void              SetDeviationInPoints(const ulong deviation) { m_deviation=deviation;            }
   void              SetTypeFilling(const ENUM_ORDER_TYPE_FILLING filling) { m_type_filling=filling; }
   bool              SetTypeFillingBySymbol(const string symbol);
   void              SetMarginMode(void) { m_margin_mode=(ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE); }
   //--- methods for working with positions
   bool              PositionOpen(const string symbol,const ENUM_ORDER_TYPE order_type,const double volume,
                                  const double price,const double sl,const double tp,const string comment="");
   bool              PositionModify(const string symbol,const double sl,const double tp);
   bool              PositionModify(const ulong ticket,const double sl,const double tp);
   bool              PositionClose(const string symbol,const ulong deviation=ULONG_MAX);
   bool              PositionClose(const ulong ticket,const ulong deviation=ULONG_MAX);
   bool              PositionCloseBy(const ulong ticket,const ulong ticket_by);
   bool              PositionClosePartial(const string symbol,const double volume,const ulong deviation=ULONG_MAX);
   bool              PositionClosePartial(const ulong ticket,const double volume,const ulong deviation=ULONG_MAX);
   //--- methods for working with pending orders
   bool              OrderOpen(const string symbol,const ENUM_ORDER_TYPE order_type,const double volume,
                               const double limit_price,const double price,const double sl,const double tp,
                               ENUM_ORDER_TYPE_TIME type_time=ORDER_TIME_GTC,const datetime expiration=0,
                               const string comment="");
   bool              OrderModify(const ulong ticket,const double price,const double sl,const double tp,
                                 const ENUM_ORDER_TYPE_TIME type_time,const datetime expiration,const double stoplimit=0.0);
   bool              OrderDelete(const ulong ticket);
   //--- additions methods
   bool              Buy(const double volume,const string symbol=NULL,double price=0.0,const double sl=0.0,const double tp=0.0,const string comment="");
   bool              Sell(const double volume,const string symbol=NULL,double price=0.0,const double sl=0.0,const double tp=0.0,const string comment="");
   bool              BuyLimit(const double volume,const double price,const string symbol=NULL,const double sl=0.0,const double tp=0.0,
                              const ENUM_ORDER_TYPE_TIME type_time=ORDER_TIME_GTC,const datetime expiration=0,const string comment="");
   bool              BuyStop(const double volume,const double price,const string symbol=NULL,const double sl=0.0,const double tp=0.0,
                             const ENUM_ORDER_TYPE_TIME type_time=ORDER_TIME_GTC,const datetime expiration=0,const string comment="");
   bool              SellLimit(const double volume,const double price,const string symbol=NULL,const double sl=0.0,const double tp=0.0,
                               const ENUM_ORDER_TYPE_TIME type_time=ORDER_TIME_GTC,const datetime expiration=0,const string comment="");
   bool              SellStop(const double volume,const double price,const string symbol=NULL,const double sl=0.0,const double tp=0.0,
                              const ENUM_ORDER_TYPE_TIME type_time=ORDER_TIME_GTC,const datetime expiration=0,const string comment="");
   //--- method check
   virtual double    CheckVolume(const string symbol,double volume,double price,ENUM_ORDER_TYPE order_type);
   virtual bool      OrderCheck(const MqlTradeRequest &request,MqlTradeCheckResult &check_result);
   virtual bool      OrderSend(const MqlTradeRequest &request,MqlTradeResult &result);
   //--- info methods
   void              PrintRequest(void) const;
   void              PrintResult(void) const;
   //--- positions
   string            FormatPositionType(string &str,const uint type) const;
   //--- orders
   string            FormatOrderType(string &str,const uint type) const;
   string            FormatOrderStatus(string &str,const uint status) const;
   string            FormatOrderTypeFilling(string &str,const uint type) const;
   string            FormatOrderTypeTime(string &str,const uint type) const;
   string            FormatOrderPrice(string &str,const double price_order,const double price_trigger,const uint digits) const;
   //--- trade request
   string            FormatRequest(string &str,const MqlTradeRequest &request) const;
   string            FormatRequestResult(string &str,const MqlTradeRequest &request,const MqlTradeResult &result) const;

protected:
   bool              FillingCheck(const string symbol);
   bool              ExpirationCheck(const string symbol);
   bool              OrderTypeCheck(const string symbol);
   void              ClearStructures(void);
   bool              IsStopped(const string function);
   bool              IsHedging(void) const { return(m_margin_mode==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING); }
   //--- position select depending on netting or hedging
   bool              SelectPosition(const string symbol);
  };
//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CTrade::CTrade(void) : m_async_mode(false),
                       m_magic(0),
                       m_deviation(10),
                       m_type_filling(ORDER_FILLING_FOK),
                       m_log_level(LOG_LEVEL_ERRORS)
  {
   SetMarginMode();
//--- initialize protected data
   ClearStructures();
//--- check programm mode
   if(MQLInfoInteger(ENUM_MQL_INFO_INTEGER::MQL_TESTER))
      m_log_level=LOG_LEVEL_ALL;
   if(MQLInfoInteger(ENUM_MQL_INFO_INTEGER::MQL_OPTIMIZATION))
      m_log_level=LOG_LEVEL_NO;
  }
//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CTrade::~CTrade(void)
  {
  }
//+------------------------------------------------------------------+
//| Get the request structure                                        |
//+------------------------------------------------------------------+
void CTrade::Request(MqlTradeRequest &request) const
  {
   request.action      =m_request.action;
   request.magic       =m_request.magic;
   request.order       =m_request.order;
   request.symbol      =m_request.symbol;
   request.volume      =m_request.volume;
   request.price       =m_request.price;
   request.stoplimit   =m_request.stoplimit;
   request.sl          =m_request.sl;
   request.tp          =m_request.tp;
   request.deviation   =m_request.deviation;
   request.type        =m_request.type;
   request.type_filling=m_request.type_filling;
   request.type_time   =m_request.type_time;
   request.expiration  =m_request.expiration;
   request.comment     =m_request.comment;
   request.position    =m_request.position;
   request.position_by =m_request.position_by;
  }
//+------------------------------------------------------------------+
//| Get the trade action as string                                   |
//+------------------------------------------------------------------+
string CTrade::RequestActionDescription(void) const
  {
   string str;
//---
   FormatRequest(str,m_request);
//---
   return(str);
  }
//+------------------------------------------------------------------+
//| Get the order type as string                                     |
//+------------------------------------------------------------------+
string CTrade::RequestTypeDescription(void) const
  {
   string str;
//---
   FormatOrderType(str,(uint)m_request.order);
//---
   return(str);
  }
//+------------------------------------------------------------------+
//| Get the order type filling as string                             |
//+------------------------------------------------------------------+
string CTrade::RequestTypeFillingDescription(void) const
  {
   string str;
//---
   FormatOrderTypeFilling(str,m_request.type_filling);
//---
   return(str);
  }
//+------------------------------------------------------------------+
//| Get the order type time as string                                |
//+------------------------------------------------------------------+
string CTrade::RequestTypeTimeDescription(void) const
  {
   string str;
//---
   FormatOrderTypeTime(str,m_request.type_time);
//---
   return(str);
  }
//+------------------------------------------------------------------+
//| Get the result structure                                         |
//+------------------------------------------------------------------+
void CTrade::Result(MqlTradeResult &result) const
  {
   result.retcode   =m_result.retcode;
   result.deal      =m_result.deal;
   result.order     =m_result.order;
   result.volume    =m_result.volume;
   result.price     =m_result.price;
   result.bid       =m_result.bid;
   result.ask       =m_result.ask;
   result.comment   =m_result.comment;
   result.request_id=m_result.request_id;
   result.retcode_external=m_result.retcode_external;
  }
//+------------------------------------------------------------------+
//| Get the retcode value as string                                  |
//+------------------------------------------------------------------+
string CTrade::ResultRetcodeDescription(void) const
  {
   string str;
//---
   FormatRequestResult(str,m_request,m_result);
//---
   return(str);
  }
//+------------------------------------------------------------------+
//| Get the check result structure                                   |
//+------------------------------------------------------------------+
void CTrade::CheckResult(MqlTradeCheckResult &check_result) const
  {
//--- copy structure
   check_result.retcode     =m_check_result.retcode;
   check_result.balance     =m_check_result.balance;
   check_result.equity      =m_check_result.equity;
   check_result.profit      =m_check_result.profit;
   check_result.margin      =m_check_result.margin;
   check_result.margin_free =m_check_result.margin_free;
   check_result.margin_level=m_check_result.margin_level;
   check_result.comment     =m_check_result.comment;
  }
//+------------------------------------------------------------------+
//| Get the check retcode value as string                            |
//+------------------------------------------------------------------+
string CTrade::CheckResultRetcodeDescription(void) const
  {
   string         str;
   MqlTradeResult result;
//---
   result.retcode=m_check_result.retcode;
   FormatRequestResult(str,m_request,result);
//---
   return(str);
  }
//+------------------------------------------------------------------+
//| Open position                                                    |
//+------------------------------------------------------------------+
bool CTrade::PositionOpen(const string symbol,const ENUM_ORDER_TYPE order_type,const double volume,
                          const double price,const double sl,const double tp,const string comment)
  {
//--- check stopped
   if(IsStopped(__FUNCTION__))
      return(false);
//--- clean
   ClearStructures();
//--- check
   if(order_type!=ORDER_TYPE_BUY && order_type!=ORDER_TYPE_SELL)
     {
      m_result.retcode=TRADE_RETCODE_INVALID;
      m_result.comment="Invalid order type";
      return(false);
     }
//--- setting request
   m_request.action   =TRADE_ACTION_DEAL;
   m_request.symbol   =symbol;
   m_request.magic    =m_magic;
   m_request.volume   =volume;
   m_request.type     =order_type;
   m_request.price    =price;
   m_request.sl       =sl;
   m_request.tp       =tp;
   m_request.deviation=m_deviation;
//--- check order type
   if(!OrderTypeCheck(symbol))
      return(false);
//--- check filling
   if(!FillingCheck(symbol))
      return(false);
   m_request.comment=comment;
//--- action and return the result
   return(OrderSend(m_request,m_result));
  }
//+------------------------------------------------------------------+
//| Modify specified opened position                                 |
//+------------------------------------------------------------------+
bool CTrade::PositionModify(const string symbol,const double sl,const double tp)
  {
//--- check stopped
   if(IsStopped(__FUNCTION__))
      return(false);
//--- check position existence
   if(!SelectPosition(symbol))
      return(false);
//--- clean
   ClearStructures();
//--- setting request
   m_request.action  =TRADE_ACTION_SLTP;
   m_request.symbol  =symbol;
   m_request.magic   =m_magic;
   m_request.sl      =sl;
   m_request.tp      =tp;
   m_request.position=PositionGetInteger(POSITION_TICKET);
//--- action and return the result
   return(OrderSend(m_request,m_result));
  }
//+------------------------------------------------------------------+
//| Modify specified opened position                                 |
//+------------------------------------------------------------------+
bool CTrade::PositionModify(const ulong ticket,const double sl,const double tp)
  {
//--- check stopped
   if(IsStopped(__FUNCTION__))
      return(false);
//--- check position existence
   if(!PositionSelectByTicket(ticket))
      return(false);
//--- clean
   ClearStructures();
//--- setting request
   m_request.action  =TRADE_ACTION_SLTP;
   m_request.position=ticket;
   m_request.symbol  =PositionGetString(POSITION_SYMBOL);
   m_request.magic   =m_magic;
   m_request.sl      =sl;
   m_request.tp      =tp;
//--- action and return the result
   return(OrderSend(m_request,m_result));
  }
//+------------------------------------------------------------------+
//| Close specified opened position                                  |
//+------------------------------------------------------------------+
bool CTrade::PositionClose(const string symbol,const ulong deviation)
  {
   bool partial_close=false;
   int  retry_count  =10;
   uint retcode      =TRADE_RETCODE_REJECT;
//--- check stopped
   if(IsStopped(__FUNCTION__))
      return(false);
//--- clean
   ClearStructures();
//--- check filling
   if(!FillingCheck(symbol))
      return(false);
   do
     {
      //--- check
      if(SelectPosition(symbol))
        {
         if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)
           {
            //--- prepare request for close BUY position
            m_request.type =ORDER_TYPE_SELL;
            m_request.price=SymbolInfoDouble(symbol,SYMBOL_BID);
           }
         else
           {
            //--- prepare request for close SELL position
            m_request.type =ORDER_TYPE_BUY;
            m_request.price=SymbolInfoDouble(symbol,SYMBOL_ASK);
           }
        }
      else
        {
         //--- position not found
         m_result.retcode=retcode;
         return(false);
        }
      //--- setting request
      m_request.action   =TRADE_ACTION_DEAL;
      m_request.symbol   =symbol;
      m_request.volume   =PositionGetDouble(POSITION_VOLUME);
      m_request.magic    =m_magic;
      m_request.deviation=(deviation==ULONG_MAX) ? m_deviation : deviation;
      m_request.position =PositionGetInteger(POSITION_TICKET);
      //--- check volume
      double max_volume=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
      if(m_request.volume>max_volume)
        {
         m_request.volume=max_volume;
         partial_close=true;
        }
      else
         partial_close=false;
      //--- hedging? just send order
      if(IsHedging())
         return(OrderSend(m_request,m_result));
      //--- order send
      if(!OrderSend(m_request,m_result))
        {
         if(--retry_count!=0)
            continue;
         if(retcode==TRADE_RETCODE_DONE_PARTIAL)
            m_result.retcode=retcode;
         return(false);
        }
      //--- WARNING. If position volume exceeds the maximum volume allowed for deal,
      //--- and when the asynchronous trade mode is on, for safety reasons, position is closed not completely,
      //--- but partially. It is decreased by the maximum volume allowed for deal.
      if(m_async_mode)
         break;
      retcode=TRADE_RETCODE_DONE_PARTIAL;
      if(partial_close)
         Sleep(1000);
     }
   while(partial_close);
//--- succeed
   return(true);
  }
//+------------------------------------------------------------------+
//| Close specified opened position                                  |
//+------------------------------------------------------------------+
bool CTrade::PositionClose(const ulong ticket,const ulong deviation)
  {
//--- check stopped
   if(IsStopped(__FUNCTION__))
      return(false);
//--- check position existence
   if(!PositionSelectByTicket(ticket))
      return(false);
   string symbol=PositionGetString(POSITION_SYMBOL);
//--- clean
   ClearStructures();
//--- check filling
   if(!FillingCheck(symbol))
      return(false);
//--- check
   if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)
     {
      //--- prepare request for close BUY position
      m_request.type =ORDER_TYPE_SELL;
      m_request.price=SymbolInfoDouble(symbol,SYMBOL_BID);
     }
   else
     {
      //--- prepare request for close SELL position
      m_request.type =ORDER_TYPE_BUY;
      m_request.price=SymbolInfoDouble(symbol,SYMBOL_ASK);
     }
//--- setting request
   m_request.action   =TRADE_ACTION_DEAL;
   m_request.position =ticket;
   m_request.symbol   =symbol;
   m_request.volume   =PositionGetDouble(POSITION_VOLUME);
   m_request.magic    =m_magic;
   m_request.deviation=(deviation==ULONG_MAX) ? m_deviation : deviation;
//--- close position
   return(OrderSend(m_request,m_result));
  }
//+------------------------------------------------------------------+
//| Close one position by other                                      |
//+------------------------------------------------------------------+
bool CTrade::PositionCloseBy(const ulong ticket,const ulong ticket_by)
  {
//--- check stopped
   if(IsStopped(__FUNCTION__))
      return(false);
//--- check hedging mode
   if(!IsHedging())
      return(false);
//--- check position existence
   if(!PositionSelectByTicket(ticket))
      return(false);
   string symbol=PositionGetString(POSITION_SYMBOL);
   ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   if(!PositionSelectByTicket(ticket_by))
      return(false);
   string symbol_by=PositionGetString(POSITION_SYMBOL);
   ENUM_POSITION_TYPE type_by=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
//--- check positions
   if(type==type_by)
      return(false);
   if(symbol!=symbol_by)
      return(false);
//--- clean
   ClearStructures();
//--- check filling
   if(!FillingCheck(symbol))
      return(false);
//--- setting request
   m_request.action     =TRADE_ACTION_CLOSE_BY;
   m_request.position   =ticket;
   m_request.position_by=ticket_by;
   m_request.magic      =m_magic;
//--- close position
   return(OrderSend(m_request,m_result));
  }
//+------------------------------------------------------------------+
//| Partial close specified opened position (for hedging mode only)  |
//+------------------------------------------------------------------+
bool CTrade::PositionClosePartial(const string symbol,const double volume,const ulong deviation)
  {
   uint retcode=TRADE_RETCODE_REJECT;
//--- check stopped
   if(IsStopped(__FUNCTION__))
      return(false);
//--- for hedging mode only
   if(!IsHedging())
      return(false);
//--- clean
   ClearStructures();
//--- check filling
   if(!FillingCheck(symbol))
      return(false);
//--- check
   if(SelectPosition(symbol))
     {
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)
        {
         //--- prepare request for close BUY position
         m_request.type =ORDER_TYPE_SELL;
         m_request.price=SymbolInfoDouble(symbol,SYMBOL_BID);
        }
      else
        {
         //--- prepare request for close SELL position
         m_request.type =ORDER_TYPE_BUY;
         m_request.price=SymbolInfoDouble(symbol,SYMBOL_ASK);
        }
     }
   else
     {
      //--- position not found
      m_result.retcode=retcode;
      return(false);
     }
//--- check volume
   double position_volume=PositionGetDouble(POSITION_VOLUME);
   if(position_volume>volume)
      position_volume=volume;
//--- setting request
   m_request.action   =TRADE_ACTION_DEAL;
   m_request.symbol   =symbol;
   m_request.volume   =position_volume;
   m_request.magic    =m_magic;
   m_request.deviation=(deviation==ULONG_MAX) ? m_deviation : deviation;
   m_request.position =PositionGetInteger(POSITION_TICKET);
//--- hedging? just send order
   return(OrderSend(m_request,m_result));
  }
//+------------------------------------------------------------------+
//| Partial close specified opened position (for hedging mode only)  |
//+------------------------------------------------------------------+
bool CTrade::PositionClosePartial(const ulong ticket,const double volume,const ulong deviation)
  {
//--- check stopped
   if(IsStopped(__FUNCTION__))
      return(false);
//--- for hedging mode only
   if(!IsHedging())
      return(false);
//--- check position existence
   if(!PositionSelectByTicket(ticket))
      return(false);
   string symbol=PositionGetString(POSITION_SYMBOL);
//--- clean
   ClearStructures();
//--- check filling
   if(!FillingCheck(symbol))
      return(false);
//--- check
   if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)
     {
      //--- prepare request for close BUY position
      m_request.type =ORDER_TYPE_SELL;
      m_request.price=SymbolInfoDouble(symbol,SYMBOL_BID);
     }
   else
     {
      //--- prepare request for close SELL position
      m_request.type =ORDER_TYPE_BUY;
      m_request.price=SymbolInfoDouble(symbol,SYMBOL_ASK);
     }
//--- check volume
   double position_volume=PositionGetDouble(POSITION_VOLUME);
   if(position_volume>volume)
      position_volume=volume;
//--- setting request
   m_request.action   =TRADE_ACTION_DEAL;
   m_request.position =ticket;
   m_request.symbol   =symbol;
   m_request.volume   =position_volume;
   m_request.magic    =m_magic;
   m_request.deviation=(deviation==ULONG_MAX) ? m_deviation : deviation;
//--- close position
   return(OrderSend(m_request,m_result));
  }
//+------------------------------------------------------------------+
//| Installation pending order                                       |
//+------------------------------------------------------------------+
bool CTrade::OrderOpen(const string symbol,const ENUM_ORDER_TYPE order_type,const double volume,const double limit_price,
                       const double price,const double sl,const double tp,
                       ENUM_ORDER_TYPE_TIME type_time,const datetime expiration,const string comment)
  {
//--- check stopped
   if(IsStopped(__FUNCTION__))
      return(false);
//--- clean
   ClearStructures();
//--- check filling
   if(!FillingCheck(symbol))
      return(false);
//--- check order type
   if(order_type==ORDER_TYPE_BUY || order_type==ORDER_TYPE_SELL)
     {
      m_result.retcode=TRADE_RETCODE_INVALID;
      m_result.comment="Invalid order type";
      return(false);
     }
//--- check order expiration
   if(type_time==ORDER_TIME_GTC && expiration==0)
     {
      int exp=(int)SymbolInfoInteger(symbol,SYMBOL_EXPIRATION_MODE);
      if((exp&SYMBOL_EXPIRATION_GTC)!=SYMBOL_EXPIRATION_GTC)
        {
         //--- if you place order for an unlimited time and if placing of such orders is prohibited
         //--- try to place order with expiration at the end of the day
         if((exp&SYMBOL_EXPIRATION_DAY)!=SYMBOL_EXPIRATION_DAY)
           {
            //--- if even this is not possible - error
            Print(__FUNCTION__,": Error: Unable to place order without explicitly specified expiration time");
            m_result.retcode=TRADE_RETCODE_INVALID_EXPIRATION;
            m_result.comment="Invalid expiration type";
            return(false);
           }
         type_time=ORDER_TIME_DAY;
        }
     }
//--- setting request
   m_request.action      =TRADE_ACTION_PENDING;
   m_request.symbol      =symbol;
   m_request.magic       =m_magic;
   m_request.volume      =volume;
   m_request.type        =order_type;
   m_request.stoplimit   =limit_price;
   m_request.price       =price;
   m_request.sl          =sl;
   m_request.tp          =tp;
   m_request.type_time   =type_time;
   m_request.expiration  =expiration;
//--- check order type
   if(!OrderTypeCheck(symbol))
      return(false);
//--- check filling
   if(!FillingCheck(symbol))
     {
      m_result.retcode=TRADE_RETCODE_INVALID_FILL;
      Print(__FUNCTION__+": Invalid filling type");
      return(false);
     }
//--- check expiration
   if(!ExpirationCheck(symbol))
     {
      m_result.retcode=TRADE_RETCODE_INVALID_EXPIRATION;
      Print(__FUNCTION__+": Invalid expiration type");
      return(false);
     }
   m_request.comment=comment;
//--- action and return the result
   return(OrderSend(m_request,m_result));
  }
//+------------------------------------------------------------------+
//| Modify specified pending order                                   |
//+------------------------------------------------------------------+
bool CTrade::OrderModify(const ulong ticket,const double price,const double sl,const double tp,
                         const ENUM_ORDER_TYPE_TIME type_time,const datetime expiration,const double stoplimit)
  {
//--- check stopped
   if(IsStopped(__FUNCTION__))
      return(false);
//--- check order existence
   if(!OrderSelect(ticket))
      return(false);
//--- clean
   ClearStructures();
//--- setting request
   m_request.symbol      =OrderGetString(ORDER_SYMBOL);
   m_request.action      =TRADE_ACTION_MODIFY;
   m_request.magic       =m_magic;
   m_request.order       =ticket;
   m_request.price       =price;
   m_request.stoplimit   =stoplimit;
   m_request.sl          =sl;
   m_request.tp          =tp;
   m_request.type_time   =type_time;
   m_request.expiration  =expiration;
//--- action and return the result
   return(OrderSend(m_request,m_result));
  }
//+------------------------------------------------------------------+
//| Delete specified pending order                                   |
//+------------------------------------------------------------------+
bool CTrade::OrderDelete(const ulong ticket)
  {
//--- check stopped
   if(IsStopped(__FUNCTION__))
      return(false);
//--- clean
   ClearStructures();
//--- setting request
   m_request.action    =TRADE_ACTION_REMOVE;
   m_request.magic     =m_magic;
   m_request.order     =ticket;
//--- action and return the result
   return(OrderSend(m_request,m_result));
  }
//+------------------------------------------------------------------+
//| Output full information of request to log                        |
//+------------------------------------------------------------------+
void CTrade::PrintRequest(void) const
  {
   if(m_log_level<LOG_LEVEL_ALL)
      return;
//---
   string str;
   PrintFormat("%s",FormatRequest(str,m_request));
  }
//+------------------------------------------------------------------+
//| Output full information of result to log                         |
//+------------------------------------------------------------------+
void CTrade::PrintResult(void) const
  {
   if(m_log_level<LOG_LEVEL_ALL)
      return;
//---
   string str;
   PrintFormat("%s",FormatRequestResult(str,m_request,m_result));
  }
//+------------------------------------------------------------------+
//| Clear structures m_request,m_result and m_check_result           |
//+------------------------------------------------------------------+
void CTrade::ClearStructures(void)
  {
   ZeroMemory(m_request);
   ZeroMemory(m_result);
   ZeroMemory(m_check_result);
  }
//+------------------------------------------------------------------+
//| Checks forced shutdown of MQL5-program                           |
//+------------------------------------------------------------------+
bool CTrade::IsStopped(const string function)
  {
   if(!::IsStopped())
      return(false);
//--- MQL5 program is stopped
   PrintFormat("%s: MQL5 program is stopped. Trading is disabled",function);
   m_result.retcode=TRADE_RETCODE_CLIENT_DISABLES_AT;
   return(true);
  }
//+------------------------------------------------------------------+
//| Buy operation                                                    |
//+------------------------------------------------------------------+
bool CTrade::Buy(const double volume,const string symbol=NULL,double price=0.0,const double sl=0.0,const double tp=0.0,const string comment="")
  {
//--- check volume
   if(volume<=0.0)
     {
      m_result.retcode=TRADE_RETCODE_INVALID_VOLUME;
      return(false);
     }
//--- check symbol
   string symbol_name=(symbol==NULL) ? _Symbol : symbol;
//--- check price
   if(price==0.0)
      price=SymbolInfoDouble(symbol_name,SYMBOL_ASK);
//---
   return(PositionOpen(symbol_name,ORDER_TYPE_BUY,volume,price,sl,tp,comment));
  }
//+------------------------------------------------------------------+
//| Sell operation                                                   |
//+------------------------------------------------------------------+
bool CTrade::Sell(const double volume,const string symbol=NULL,double price=0.0,const double sl=0.0,const double tp=0.0,const string comment="")
  {
//--- check volume
   if(volume<=0.0)
     {
      m_result.retcode=TRADE_RETCODE_INVALID_VOLUME;
      return(false);
     }
//--- check symbol
   string symbol_name=(symbol==NULL) ? _Symbol : symbol;
//--- check price
   if(price==0.0)
      price=SymbolInfoDouble(symbol_name,SYMBOL_BID);
//---
   return(PositionOpen(symbol_name,ORDER_TYPE_SELL,volume,price,sl,tp,comment));
  }
//+------------------------------------------------------------------+
//| Send BUY_LIMIT order                                             |
//+------------------------------------------------------------------+
bool CTrade::BuyLimit(const double volume,const double price,const string symbol=NULL,const double sl=0.0,const double tp=0.0,
                      const ENUM_ORDER_TYPE_TIME type_time=ORDER_TIME_GTC,const datetime expiration=0,const string comment="")
  {
   string symbol_name;
//--- check volume
   if(volume<=0.0)
     {
      m_result.retcode=TRADE_RETCODE_INVALID_VOLUME;
      return(false);
     }
//--- check symbol
   symbol_name=(symbol==NULL)?Symbol():symbol;
//--- send "BUY_LIMIT" order
   return(OrderOpen(symbol_name,ORDER_TYPE_BUY_LIMIT,volume,0.0,price,sl,tp,type_time,expiration,comment));
  }
//+------------------------------------------------------------------+
//| Send BUY_STOP order                                              |
//+------------------------------------------------------------------+
bool CTrade::BuyStop(const double volume,const double price,const string symbol=NULL,const double sl=0.0,const double tp=0.0,
                     const ENUM_ORDER_TYPE_TIME type_time=ORDER_TIME_GTC,const datetime expiration=0,const string comment="")
  {
   string symbol_name;
//--- check volume
   if(volume<=0.0)
     {
      m_result.retcode=TRADE_RETCODE_INVALID_VOLUME;
      return(false);
     }
//--- check symbol
   symbol_name=(symbol==NULL)?Symbol():symbol;
//--- send "BUY_STOP" order
   return(OrderOpen(symbol_name,ORDER_TYPE_BUY_STOP,volume,0.0,price,sl,tp,type_time,expiration,comment));
  }
//+------------------------------------------------------------------+
//| Send SELL_LIMIT order                                            |
//+------------------------------------------------------------------+
bool CTrade::SellLimit(const double volume,const double price,const string symbol=NULL,const double sl=0.0,const double tp=0.0,
                       const ENUM_ORDER_TYPE_TIME type_time=ORDER_TIME_GTC,const datetime expiration=0,const string comment="")
  {
   string symbol_name;
//--- check volume
   if(volume<=0.0)
     {
      m_result.retcode=TRADE_RETCODE_INVALID_VOLUME;
      return(false);
     }
//--- check symbol
   symbol_name=(symbol==NULL)?Symbol():symbol;
//--- send "SELL_LIMIT" order
   return(OrderOpen(symbol_name,ORDER_TYPE_SELL_LIMIT,volume,0.0,price,sl,tp,type_time,expiration,comment));
  }
//+------------------------------------------------------------------+
//| Send SELL_STOP order                                             |
//+------------------------------------------------------------------+
bool CTrade::SellStop(const double volume,const double price,const string symbol=NULL,const double sl=0.0,const double tp=0.0,
                      const ENUM_ORDER_TYPE_TIME type_time=ORDER_TIME_GTC,const datetime expiration=0,const string comment="")
  {
   string symbol_name;
//--- check volume
   if(volume<=0.0)
     {
      m_result.retcode=TRADE_RETCODE_INVALID_VOLUME;
      return(false);
     }
//--- check symbol
   symbol_name=(symbol==NULL)?Symbol():symbol;
//--- send "SELL_STOP" order
   return(OrderOpen(symbol_name,ORDER_TYPE_SELL_STOP,volume,0.0,price,sl,tp,type_time,expiration,comment));
  }
//+------------------------------------------------------------------+
//| Converts the position type to text                               |
//+------------------------------------------------------------------+
string CTrade::FormatPositionType(string &str,const uint type) const
  {
//--- see the type
   switch(type)
     {
      case POSITION_TYPE_BUY:
         str="buy";
         break;
      case POSITION_TYPE_SELL:
         str="sell";
         break;
      default:
         str="unknown position type "+(string)type;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the order type to text                                  |
//+------------------------------------------------------------------+
string CTrade::FormatOrderType(string &str,const uint type) const
  {
//--- see the type
   switch(type)
     {
      case ORDER_TYPE_BUY:
         str="buy";
         break;
      case ORDER_TYPE_SELL:
         str="sell";
         break;
      case ORDER_TYPE_BUY_LIMIT:
         str="buy limit";
         break;
      case ORDER_TYPE_SELL_LIMIT:
         str="sell limit";
         break;
      case ORDER_TYPE_BUY_STOP:
         str="buy stop";
         break;
      case ORDER_TYPE_SELL_STOP:
         str="sell stop";
         break;
      case ORDER_TYPE_BUY_STOP_LIMIT:
         str="buy stop limit";
         break;
      case ORDER_TYPE_SELL_STOP_LIMIT:
         str="sell stop limit";
         break;
      default:
         str="unknown order type "+(string)type;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the order filling type to text                          |
//+------------------------------------------------------------------+
string CTrade::FormatOrderTypeFilling(string &str,const uint type) const
  {
//--- see the type
   switch(type)
     {
      case ORDER_FILLING_RETURN:
         str="return remainder";
         break;
      case ORDER_FILLING_IOC:
         str="cancel remainder";
         break;
      case ORDER_FILLING_FOK:
         str="fill or kill";
         break;
      default:
         str="unknown type filling "+(string)type;
         break;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the type of order by expiration to text                 |
//+------------------------------------------------------------------+
string CTrade::FormatOrderTypeTime(string &str,const uint type) const
  {
//--- see the type
   switch(type)
     {
      case ORDER_TIME_GTC:
         str="gtc";
         break;
      case ORDER_TIME_DAY:
         str="day";
         break;
      case ORDER_TIME_SPECIFIED:
         str="specified";
         break;
      case ORDER_TIME_SPECIFIED_DAY:
         str="specified day";
         break;
      default:
         str="unknown type time "+(string)type;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the order prices to text                                |
//+------------------------------------------------------------------+
string CTrade::FormatOrderPrice(string &str,const double price_order,const double price_trigger,const uint digits) const
  {
   string price,trigger;
//--- Is there its trigger price?
   if(price_trigger)
     {
      price  =DoubleToString(price_order,digits);
      trigger=DoubleToString(price_trigger,digits);
      str    =StringFormat("%s (%s)",price,trigger);
     }
   else
      str=DoubleToString(price_order,digits);
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the parameters of a trade request to text               |
//+------------------------------------------------------------------+
string CTrade::FormatRequest(string &str,const MqlTradeRequest &request) const
  {
   string type,price,price_new;
   string tmp_string;
   long   tmp_long;
//--- clean
   str="";
//--- set up
   string symbol_name=(request.symbol==NULL) ? _Symbol : request.symbol;
   int    digits=_Digits;
   ENUM_SYMBOL_TRADE_EXECUTION trade_execution=0;
   if(SymbolInfoInteger(symbol_name,SYMBOL_DIGITS,tmp_long))
      digits=(int)tmp_long;
   if(SymbolInfoInteger(symbol_name,SYMBOL_TRADE_EXEMODE,tmp_long))
      trade_execution=(ENUM_SYMBOL_TRADE_EXECUTION)tmp_long;
//--- see what is wanted
   switch(request.action)
     {
      //--- instant execution of a deal
      case TRADE_ACTION_DEAL:
         switch(trade_execution)
           {
            //--- request execution
            case SYMBOL_TRADE_EXECUTION_REQUEST:
               if(IsHedging() && request.position!=0)
                  str=StringFormat("request %s %s position #%I64u %s at %s",
                                   FormatOrderType(type,request.type),
                                   DoubleToString(request.volume,2),
                                   request.position,
                                   request.symbol,
                                   DoubleToString(request.price,digits));
               else
                  str=StringFormat("request %s %s %s at %s",
                                   FormatOrderType(type,request.type),
                                   DoubleToString(request.volume,2),
                                   request.symbol,
                                   DoubleToString(request.price,digits));
               //--- Is there SL or TP?
               if(request.sl!=0.0)
                 {
                  tmp_string=StringFormat(" sl: %s",DoubleToString(request.sl,digits));
                  str+=tmp_string;
                 }
               if(request.tp!=0.0)
                 {
                  tmp_string=StringFormat(" tp: %s",DoubleToString(request.tp,digits));
                  str+=tmp_string;
                 }
               break;
            //--- instant execution
            case SYMBOL_TRADE_EXECUTION_INSTANT:
               if(IsHedging() && request.position!=0)
                  str=StringFormat("instant %s %s position #%I64u %s at %s",
                                   FormatOrderType(type,request.type),
                                   DoubleToString(request.volume,2),
                                   request.position,
                                   request.symbol,
                                   DoubleToString(request.price,digits));
               else
                  str=StringFormat("instant %s %s %s at %s",
                                   FormatOrderType(type,request.type),
                                   DoubleToString(request.volume,2),
                                   request.symbol,
                                   DoubleToString(request.price,digits));
               //--- Is there SL or TP?
               if(request.sl!=0.0)
                 {
                  tmp_string=StringFormat(" sl: %s",DoubleToString(request.sl,digits));
                  str+=tmp_string;
                 }
               if(request.tp!=0.0)
                 {
                  tmp_string=StringFormat(" tp: %s",DoubleToString(request.tp,digits));
                  str+=tmp_string;
                 }
               break;
            //--- market execution
            case SYMBOL_TRADE_EXECUTION_MARKET:
               if(IsHedging() && request.position!=0)
                  str=StringFormat("market %s %s position #%I64u %s",
                                   FormatOrderType(type,request.type),
                                   DoubleToString(request.volume,2),
                                   request.position,
                                   request.symbol);
               else
                  str=StringFormat("market %s %s %s",
                                   FormatOrderType(type,request.type),
                                   DoubleToString(request.volume,2),
                                   request.symbol);
               //--- Is there SL or TP?
               if(request.sl!=0.0)
                 {
                  tmp_string=StringFormat(" sl: %s",DoubleToString(request.sl,digits));
                  str+=tmp_string;
                 }
               if(request.tp!=0.0)
                 {
                  tmp_string=StringFormat(" tp: %s",DoubleToString(request.tp,digits));
                  str+=tmp_string;
                 }
               break;
            //--- exchange execution
            case SYMBOL_TRADE_EXECUTION_EXCHANGE:
               if(IsHedging() && request.position!=0)
                  str=StringFormat("exchange %s %s position #%I64u %s",
                                   FormatOrderType(type,request.type),
                                   DoubleToString(request.volume,2),
                                   request.position,
                                   request.symbol);
               else
                  str=StringFormat("exchange %s %s %s",
                                   FormatOrderType(type,request.type),
                                   DoubleToString(request.volume,2),
                                   request.symbol);
               //--- Is there SL or TP?
               if(request.sl!=0.0)
                 {
                  tmp_string=StringFormat(" sl: %s",DoubleToString(request.sl,digits));
                  str+=tmp_string;
                 }
               if(request.tp!=0.0)
                 {
                  tmp_string=StringFormat(" tp: %s",DoubleToString(request.tp,digits));
                  str+=tmp_string;
                 }
               break;
           }
         //--- end of TRADE_ACTION_DEAL processing
         break;

      //--- setting a pending order
      case TRADE_ACTION_PENDING:
         str=StringFormat("%s %s %s at %s",
                          FormatOrderType(type,request.type),
                          DoubleToString(request.volume,2),
                          request.symbol,
                          FormatOrderPrice(price,request.price,request.stoplimit,digits));
         //--- Is there SL or TP?
         if(request.sl!=0.0)
           {
            tmp_string=StringFormat(" sl: %s",DoubleToString(request.sl,digits));
            str+=tmp_string;
           }
         if(request.tp!=0.0)
           {
            tmp_string=StringFormat(" tp: %s",DoubleToString(request.tp,digits));
            str+=tmp_string;
           }
         break;

      //--- Setting SL/TP
      case TRADE_ACTION_SLTP:
         if(IsHedging() && request.position!=0)
            str=StringFormat("modify position #%I64u %s (sl: %s, tp: %s)",
                             request.position,
                             request.symbol,
                             DoubleToString(request.sl,digits),
                             DoubleToString(request.tp,digits));
         else
            str=StringFormat("modify %s (sl: %s, tp: %s)",
                             request.symbol,
                             DoubleToString(request.sl,digits),
                             DoubleToString(request.tp,digits));
         break;

      //--- modifying a pending order
      case TRADE_ACTION_MODIFY:
         str=StringFormat("modify #%I64u at %s (sl: %s tp: %s)",
                          request.order,
                          FormatOrderPrice(price_new,request.price,request.stoplimit,digits),
                          DoubleToString(request.sl,digits),
                          DoubleToString(request.tp,digits));
         break;

      //--- deleting a pending order
      case TRADE_ACTION_REMOVE:
         str=StringFormat("cancel #%I64u",request.order);
         break;

      //--- close by
      case TRADE_ACTION_CLOSE_BY:
         if(IsHedging() && request.position!=0)
            str=StringFormat("close position #%I64u by #%I64u",request.position,request.position_by);
         else
            str=StringFormat("wrong action close by (#%I64u by #%I64u)",request.position,request.position_by);
         break;

      default:
         str="unknown action "+(string)request.action;
         break;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the result of a request to text                         |
//+------------------------------------------------------------------+
string CTrade::FormatRequestResult(string &str,const MqlTradeRequest &request,const MqlTradeResult &result) const
  {
//--- set up
   string symbol_name=(request.symbol==NULL) ? _Symbol : request.symbol;
   int    digits=_Digits;
   long   tmp_long;
   ENUM_SYMBOL_TRADE_EXECUTION trade_execution=0;
   if(SymbolInfoInteger(symbol_name,SYMBOL_DIGITS,tmp_long))
      digits=(int)tmp_long;
   if(SymbolInfoInteger(symbol_name,SYMBOL_TRADE_EXEMODE,tmp_long))
      trade_execution=(ENUM_SYMBOL_TRADE_EXECUTION)tmp_long;
//--- see the response code
   switch(result.retcode)
     {
      case TRADE_RETCODE_REQUOTE:
         str=StringFormat("requote (%s/%s)",
                          DoubleToString(result.bid,digits),
                          DoubleToString(result.ask,digits));
         break;

      case TRADE_RETCODE_DONE:
         if(request.action==TRADE_ACTION_DEAL &&
            (trade_execution==SYMBOL_TRADE_EXECUTION_REQUEST ||
             trade_execution==SYMBOL_TRADE_EXECUTION_INSTANT ||
             trade_execution==SYMBOL_TRADE_EXECUTION_MARKET))
            str=StringFormat("done at %s",DoubleToString(result.price,digits));
         else
            str="done";
         break;

      case TRADE_RETCODE_DONE_PARTIAL:
         if(request.action==TRADE_ACTION_DEAL &&
            (trade_execution==SYMBOL_TRADE_EXECUTION_REQUEST ||
             trade_execution==SYMBOL_TRADE_EXECUTION_INSTANT ||
             trade_execution==SYMBOL_TRADE_EXECUTION_MARKET))
            str=StringFormat("done partially %s at %s",
                             DoubleToString(result.volume,2),
                             DoubleToString(result.price,digits));
         else
            str=StringFormat("done partially %s",
                             DoubleToString(result.volume,2));
         break;

      case TRADE_RETCODE_REJECT:
         str="rejected";
         break;
      case TRADE_RETCODE_CANCEL:
         str="canceled";
         break;
      case TRADE_RETCODE_PLACED:
         str="placed";
         break;
      case TRADE_RETCODE_ERROR:
         str="common error";
         break;
      case TRADE_RETCODE_TIMEOUT:
         str="timeout";
         break;
      case TRADE_RETCODE_INVALID:
         str="invalid request";
         break;
      case TRADE_RETCODE_INVALID_VOLUME:
         str="invalid volume";
         break;
      case TRADE_RETCODE_INVALID_PRICE:
         str="invalid price";
         break;
      case TRADE_RETCODE_INVALID_STOPS:
         str="invalid stops";
         break;
      case TRADE_RETCODE_TRADE_DISABLED:
         str="trade disabled";
         break;
      case TRADE_RETCODE_MARKET_CLOSED:
         str="market closed";
         break;
      case TRADE_RETCODE_NO_MONEY:
         str="not enough money";
         break;
      case TRADE_RETCODE_PRICE_CHANGED:
         str="price changed";
         break;
      case TRADE_RETCODE_PRICE_OFF:
         str="off quotes";
         break;
      case TRADE_RETCODE_INVALID_EXPIRATION:
         str="invalid expiration";
         break;
      case TRADE_RETCODE_ORDER_CHANGED:
         str="order changed";
         break;
      case TRADE_RETCODE_TOO_MANY_REQUESTS:
         str="too many requests";
         break;
      case TRADE_RETCODE_NO_CHANGES:
         str="no changes";
         break;
      case TRADE_RETCODE_SERVER_DISABLES_AT:
         str="auto trading disabled by server";
         break;
      case TRADE_RETCODE_CLIENT_DISABLES_AT:
         str="auto trading disabled by client";
         break;
      case TRADE_RETCODE_LOCKED:
         str="locked";
         break;
      case TRADE_RETCODE_FROZEN:
         str="frozen";
         break;
      case TRADE_RETCODE_INVALID_FILL:
         str="invalid fill";
         break;
      case TRADE_RETCODE_CONNECTION:
         str="no connection";
         break;
      case TRADE_RETCODE_ONLY_REAL:
         str="only real";
         break;
      case TRADE_RETCODE_LIMIT_ORDERS:
         str="limit orders";
         break;
      case TRADE_RETCODE_LIMIT_VOLUME:
         str="limit volume";
         break;
      case TRADE_RETCODE_POSITION_CLOSED:
         str="position closed";
         break;
      case TRADE_RETCODE_INVALID_ORDER:
         str="invalid order";
         break;
      case TRADE_RETCODE_CLOSE_ORDER_EXIST:
         str="close order already exists";
         break;
      case TRADE_RETCODE_LIMIT_POSITIONS:
         str="limit positions";
         break;
      default:
         str="unknown retcode "+(string)result.retcode;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double CTrade::CheckVolume(const string symbol,double volume,double price,ENUM_ORDER_TYPE order_type)
  {
//--- check
   if(order_type!=ORDER_TYPE_BUY && order_type!=ORDER_TYPE_SELL)
      return(0.0);
   double free_margin=AccountInfoDouble(ENUM_ACCOUNT_INFO_DOUBLE::ACCOUNT_MARGIN_FREE);
   if(free_margin<=0.0)
      return(0.0);
//--- clean
   ClearStructures();
//--- setting request
   m_request.action=TRADE_ACTION_DEAL;
   m_request.symbol=symbol;
   m_request.volume=volume;
   m_request.type  =order_type;
   m_request.price =price;
//--- action and return the result
   if(!::OrderCheck(m_request,m_check_result) && m_check_result.margin_free<0.0)
     {
      double coeff=free_margin/(free_margin-m_check_result.margin_free);
      double lots=NormalizeDouble(volume*coeff,2);
      if(lots<volume)
        {
         //--- normalize and check limits
         double stepvol=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
         if(stepvol>0.0)
            volume=stepvol*(MathFloor(lots/stepvol)-1);
         //---
         double minvol=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
         if(volume<minvol)
            volume=0.0;
        }
     }
   return(volume);
  }
//+------------------------------------------------------------------+
//| Checks if the m_request structure is filled correctly            |
//+------------------------------------------------------------------+
bool CTrade::OrderCheck(const MqlTradeRequest &request,MqlTradeCheckResult &check_result)
  {
//--- action and return the result
   return(::OrderCheck(request,check_result));
  }
//+------------------------------------------------------------------+
//| Set order filling type according to symbol filling mode          |
//+------------------------------------------------------------------+
bool CTrade::SetTypeFillingBySymbol(const string symbol)
  {
//--- get possible filling policy types by symbol
   uint filling=(uint)SymbolInfoInteger(symbol,SYMBOL_FILLING_MODE);
   if((filling&SYMBOL_FILLING_FOK)==SYMBOL_FILLING_FOK)
     {
      m_type_filling=ORDER_FILLING_FOK;
      return(true);
     }
   if((filling&SYMBOL_FILLING_IOC)==SYMBOL_FILLING_IOC)
     {
      m_type_filling=ORDER_FILLING_IOC;
      return(true);
     }
//---
   return(false);
  }
//+------------------------------------------------------------------+
//| Checks and corrects type of filling policy                       |
//+------------------------------------------------------------------+
bool CTrade::FillingCheck(const string symbol)
  {
//--- get execution mode of orders by symbol
   ENUM_SYMBOL_TRADE_EXECUTION exec=(ENUM_SYMBOL_TRADE_EXECUTION)SymbolInfoInteger(symbol,SYMBOL_TRADE_EXEMODE);
//--- check execution mode
   if(exec==SYMBOL_TRADE_EXECUTION_REQUEST || exec==SYMBOL_TRADE_EXECUTION_INSTANT)
     {
      //--- neccessary filling type will be placed automatically
      return(true);
     }
//--- get possible filling policy types by symbol
   uint filling=(uint)SymbolInfoInteger(symbol,SYMBOL_FILLING_MODE);
//--- check execution mode again
   if(exec==SYMBOL_TRADE_EXECUTION_MARKET)
     {
      //--- for the MARKET execution mode
      //--- analyze order
      if(m_request.action!=TRADE_ACTION_PENDING)
        {
         //--- in case of instant execution order
         //--- if the required filling policy is supported, add it to the request
         if((filling&SYMBOL_FILLING_FOK)==SYMBOL_FILLING_FOK)
           {
            m_type_filling=ORDER_FILLING_FOK;
            m_request.type_filling=m_type_filling;
            return(true);
           }
         if((filling&SYMBOL_FILLING_IOC)==SYMBOL_FILLING_IOC)
           {
            m_type_filling=ORDER_FILLING_IOC;
            m_request.type_filling=m_type_filling;
            return(true);
           }
         //--- wrong filling policy, set error code
         m_result.retcode=TRADE_RETCODE_INVALID_FILL;
         return(false);
        }
      return(true);
     }
//--- EXCHANGE execution mode
   switch(m_type_filling)
     {
      case ORDER_FILLING_FOK:
         //--- analyze order
         if(m_request.action==TRADE_ACTION_PENDING)
           {
            //--- in case of pending order
            //--- add the expiration mode to the request
            if(!ExpirationCheck(symbol))
               m_request.type_time=ORDER_TIME_DAY;
            //--- stop order?
            if(m_request.type==ORDER_TYPE_BUY_STOP || m_request.type==ORDER_TYPE_SELL_STOP ||
               m_request.type==ORDER_TYPE_BUY_LIMIT || m_request.type==ORDER_TYPE_SELL_LIMIT)
              {
               //--- in case of stop order
               //--- add the corresponding filling policy to the request
               m_request.type_filling=ORDER_FILLING_RETURN;
               return(true);
              }
           }
         //--- in case of limit order or instant execution order
         //--- if the required filling policy is supported, add it to the request
         if((filling&SYMBOL_FILLING_FOK)==SYMBOL_FILLING_FOK)
           {
            m_request.type_filling=m_type_filling;
            return(true);
           }
         //--- wrong filling policy, set error code
         m_result.retcode=TRADE_RETCODE_INVALID_FILL;
         return(false);
      case ORDER_FILLING_IOC:
         //--- analyze order
         if(m_request.action==TRADE_ACTION_PENDING)
           {
            //--- in case of pending order
            //--- add the expiration mode to the request
            if(!ExpirationCheck(symbol))
               m_request.type_time=ORDER_TIME_DAY;
            //--- stop order?
            if(m_request.type==ORDER_TYPE_BUY_STOP || m_request.type==ORDER_TYPE_SELL_STOP ||
               m_request.type==ORDER_TYPE_BUY_LIMIT || m_request.type==ORDER_TYPE_SELL_LIMIT)
              {
               //--- in case of stop order
               //--- add the corresponding filling policy to the request
               m_request.type_filling=ORDER_FILLING_RETURN;
               return(true);
              }
           }
         //--- in case of limit order or instant execution order
         //--- if the required filling policy is supported, add it to the request
         if((filling&SYMBOL_FILLING_IOC)==SYMBOL_FILLING_IOC)
           {
            m_request.type_filling=m_type_filling;
            return(true);
           }
         //--- wrong filling policy, set error code
         m_result.retcode=TRADE_RETCODE_INVALID_FILL;
         return(false);
      case ORDER_FILLING_RETURN:
         //--- add filling policy to the request
         m_request.type_filling=m_type_filling;
         return(true);
     }
//--- unknown execution mode, set error code
   m_result.retcode=TRADE_RETCODE_ERROR;
   return(false);
  }
//+------------------------------------------------------------------+
//| Check expiration type of pending order                           |
//+------------------------------------------------------------------+
bool CTrade::ExpirationCheck(const string symbol)
  {
//--- check symbol
   string symbol_name=(symbol==NULL) ? _Symbol : symbol;
//--- get flags
   long tmp_long;
   int  flags=0;
   if(SymbolInfoInteger(symbol_name,SYMBOL_EXPIRATION_MODE,tmp_long))
      flags=(int)tmp_long;
//--- check type
   switch(m_request.type_time)
     {
      case ORDER_TIME_GTC:
         if((flags&SYMBOL_EXPIRATION_GTC)!=0)
            return(true);
         break;
      case ORDER_TIME_DAY:
         if((flags&SYMBOL_EXPIRATION_DAY)!=0)
            return(true);
         break;
      case ORDER_TIME_SPECIFIED:
         if((flags&SYMBOL_EXPIRATION_SPECIFIED)!=0)
            return(true);
         break;
      case ORDER_TIME_SPECIFIED_DAY:
         if((flags&SYMBOL_EXPIRATION_SPECIFIED_DAY)!=0)
            return(true);
         break;
      default:
         Print(__FUNCTION__+": Unknown expiration type");
     }
//--- failed
   return(false);
  }
//+------------------------------------------------------------------+
//| Checks order                                                     |
//+------------------------------------------------------------------+
bool CTrade::OrderTypeCheck(const string symbol)
  {
   bool res=false;
//--- check symbol
   string symbol_name=(symbol==NULL) ? _Symbol : symbol;
//--- get flags of allowed trade orders
   long tmp_long;
   int  flags=0;
   if(SymbolInfoInteger(symbol_name,SYMBOL_ORDER_MODE,tmp_long))
      flags=(int)tmp_long;
//--- depending on the type of order in request
   switch(m_request.type)
     {
      case ORDER_TYPE_BUY:
      case ORDER_TYPE_SELL:
         //--- check possibility of execution
         res=((flags&SYMBOL_ORDER_MARKET)!=0);
         break;
      case ORDER_TYPE_BUY_LIMIT:
      case ORDER_TYPE_SELL_LIMIT:
         //--- check possibility of execution
         res=((flags&SYMBOL_ORDER_LIMIT)!=0);
         break;
      case ORDER_TYPE_BUY_STOP:
      case ORDER_TYPE_SELL_STOP:
         //--- check possibility of execution
         res=((flags&SYMBOL_ORDER_STOP)!=0);
         break;
      case ORDER_TYPE_BUY_STOP_LIMIT:
      case ORDER_TYPE_SELL_STOP_LIMIT:
         //--- check possibility of execution
         res=((flags&SYMBOL_ORDER_STOP_LIMIT)!=0);
         break;
     }
//--- check res
   if(res)
     {
      //--- trading order is valid
      //--- check if we need and able to set protective orders
      if(m_request.sl!=0.0 || m_request.tp!=0.0)
        {
         if((flags&SYMBOL_ORDER_SL)==0)
            m_request.sl=0.0;
         if((flags&SYMBOL_ORDER_TP)==0)
            m_request.tp=0.0;
        }
     }
   else
     {
      //--- trading order is not valid
      //--- set error
      m_result.retcode=TRADE_RETCODE_INVALID_ORDER;
      Print(__FUNCTION__+": Invalid order type");
     }
//--- result
   return(res);
  }
//+------------------------------------------------------------------+
//| Send order                                                       |
//+------------------------------------------------------------------+
bool CTrade::OrderSend(const MqlTradeRequest &request,MqlTradeResult &result)
  {
   bool   res;
   string action="";
   string fmt   ="";
//--- action
   if(m_async_mode)
      res=::OrderSendAsync(request,result);
   else
      res=::OrderSend(request,result);
//--- check
   if(res)
     {
      if(m_log_level>LOG_LEVEL_ERRORS)
         PrintFormat(__FUNCTION__+": %s [%s]",FormatRequest(action,request),FormatRequestResult(fmt,request,result));
     }
   else
     {
      if(m_log_level>LOG_LEVEL_NO)
         PrintFormat(__FUNCTION__+": %s [%s]",FormatRequest(action,request),FormatRequestResult(fmt,request,result));
     }
//--- return the result
   return(res);
  }
//+------------------------------------------------------------------+
//| Position select depending on netting or hedging                  |
//+------------------------------------------------------------------+
bool CTrade::SelectPosition(const string symbol)
  {
   bool res=false;
//---
   if(IsHedging())
     {
      uint total=PositionsTotal();
      for(uint i=0; i<total; i++)
        {
         string position_symbol=PositionGetSymbol(i);
         if(position_symbol==symbol && m_magic==PositionGetInteger(POSITION_MAGIC))
           {
            res=true;
            break;
           }
        }
     }
   else
      res=PositionSelect(symbol);
//---
   return(res);
  }
//+------------------------------------------------------------------+

//--- END INLINE: Trade.mqh ---
//--- INLINE: PositionInfo.mqh ---
//+------------------------------------------------------------------+
//|                                                 PositionInfo.mqh |
//|                             Copyright 2000-2026, MetaQuotes Ltd. |
//|                                                     www.mql5.com |
//+------------------------------------------------------------------+
//--- INLINE: Object.mqh ---
//+------------------------------------------------------------------+
//|                                                       Object.mqh |
//|                             Copyright 2000-2026, MetaQuotes Ltd. |
//|                                                     www.mql5.com |
//+------------------------------------------------------------------+
//--- INLINE: StdLibErr.mqh ---
//+------------------------------------------------------------------+
//|                                                    StdLibErr.mqh |
//|                             Copyright 2000-2026, MetaQuotes Ltd. |
//|                                                     www.mql5.com |
//+------------------------------------------------------------------+
#define ERR_USER_INVALID_HANDLE                            1
#define ERR_USER_INVALID_BUFF_NUM                          2
#define ERR_USER_ITEM_NOT_FOUND                            3
#define ERR_USER_ARRAY_IS_EMPTY                            1000
//+------------------------------------------------------------------+

//--- END INLINE: StdLibErr.mqh ---
//+------------------------------------------------------------------+
//| Class CObject.                                                   |
//| Purpose: Base class for storing elements.                        |
//+------------------------------------------------------------------+
class CObject
  {
private:
   CObject          *m_prev;               // previous item of list
   CObject          *m_next;               // next item of list

public:
                     CObject(void): m_prev(NULL),m_next(NULL)            {                 }
                    ~CObject(void)                                       {                 }
   //--- methods to access protected data
   CObject          *Prev(void)                                    const { return(m_prev); }
   void              Prev(CObject *node)                                 { m_prev=node;    }
   CObject          *Next(void)                                    const { return(m_next); }
   void              Next(CObject *node)                                 { m_next=node;    }
   //--- methods for working with files
   virtual bool      Save(const int file_handle)                         { return(true);   }
   virtual bool      Load(const int file_handle)                         { return(true);   }
   //--- method of identifying the object
   virtual int       Type(void)                                    const { return(0);      }
   //--- method of comparing the objects
   virtual int       Compare(const CObject *node,const int mode=0) const { return(0);      }
  };
//+------------------------------------------------------------------+

//--- END INLINE: Object.mqh ---
//+------------------------------------------------------------------+
//| Class CPositionInfo.                                             |
//| Appointment: Class for access to position info.                  |
//|              Derives from class CObject.                         |
//+------------------------------------------------------------------+
class CPositionInfo : public CObject
  {
protected:
   ENUM_POSITION_TYPE m_type;
   double            m_volume;
   double            m_price;
   double            m_stop_loss;
   double            m_take_profit;

public:
                     CPositionInfo(void);
                    ~CPositionInfo(void);
   //--- fast access methods to the integer position propertyes
   ulong             Ticket(void) const;
   datetime          Time(void) const;
   ulong             TimeMsc(void) const;
   datetime          TimeUpdate(void) const;
   ulong             TimeUpdateMsc(void) const;
   ENUM_POSITION_TYPE PositionType(void) const;
   string            TypeDescription(void) const;
   long              Magic(void) const;
   long              Identifier(void) const;
   //--- fast access methods to the double position propertyes
   double            Volume(void) const;
   double            PriceOpen(void) const;
   double            StopLoss(void) const;
   double            TakeProfit(void) const;
   double            PriceCurrent(void) const;
   double            Commission(void) const;
   double            Swap(void) const;
   double            Profit(void) const;
   //--- fast access methods to the string position propertyes
   string            Symbol(void) const;
   string            Comment(void) const;
   //--- access methods to the API MQL5 functions
   bool              InfoInteger(const ENUM_POSITION_PROPERTY_INTEGER prop_id,long &var) const;
   bool              InfoDouble(const ENUM_POSITION_PROPERTY_DOUBLE prop_id,double &var) const;
   bool              InfoString(const ENUM_POSITION_PROPERTY_STRING prop_id,string &var) const;
   //--- info methods
   string            FormatType(string &str,const uint type) const;
   string            FormatPosition(string &str) const;
   //--- methods for select position
   bool              Select(const string symbol);
   bool              SelectByMagic(const string symbol,const ulong magic);
   bool              SelectByTicket(const ulong ticket);
   bool              SelectByIndex(const int index);
   //---
   void              StoreState(void);
   bool              CheckState(void);
  };
//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CPositionInfo::CPositionInfo(void) : m_type(WRONG_VALUE),
                                     m_volume(0.0),
                                     m_price(0.0),
                                     m_stop_loss(0.0),
                                     m_take_profit(0.0)
  {
  }
//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CPositionInfo::~CPositionInfo(void)
  {
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_TICKET"                         |
//+------------------------------------------------------------------+
ulong CPositionInfo::Ticket(void) const
  {
   return((ulong)PositionGetInteger(POSITION_TICKET));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_TIME"                           |
//+------------------------------------------------------------------+
datetime CPositionInfo::Time(void) const
  {
   return((datetime)PositionGetInteger(POSITION_TIME));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_TIME_MSC"                       |
//+------------------------------------------------------------------+
ulong CPositionInfo::TimeMsc(void) const
  {
   return((ulong)PositionGetInteger(POSITION_TIME_MSC));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_TIME_UPDATE"                    |
//+------------------------------------------------------------------+
datetime CPositionInfo::TimeUpdate(void) const
  {
   return((datetime)PositionGetInteger(POSITION_TIME_UPDATE));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_TIME_UPDATE_MSC"                |
//+------------------------------------------------------------------+
ulong CPositionInfo::TimeUpdateMsc(void) const
  {
   return((ulong)PositionGetInteger(POSITION_TIME_UPDATE_MSC));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_TYPE"                           |
//+------------------------------------------------------------------+
ENUM_POSITION_TYPE CPositionInfo::PositionType(void) const
  {
   return((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_TYPE" as string                 |
//+------------------------------------------------------------------+
string CPositionInfo::TypeDescription(void) const
  {
   string str;
//---
   return(FormatType(str,PositionType()));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_MAGIC"                          |
//+------------------------------------------------------------------+
long CPositionInfo::Magic(void) const
  {
   return(PositionGetInteger(POSITION_MAGIC));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_IDENTIFIER"                     |
//+------------------------------------------------------------------+
long CPositionInfo::Identifier(void) const
  {
   return(PositionGetInteger(POSITION_IDENTIFIER));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_VOLUME"                         |
//+------------------------------------------------------------------+
double CPositionInfo::Volume(void) const
  {
   return(PositionGetDouble(POSITION_VOLUME));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_PRICE_OPEN"                     |
//+------------------------------------------------------------------+
double CPositionInfo::PriceOpen(void) const
  {
   return(PositionGetDouble(POSITION_PRICE_OPEN));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_SL"                             |
//+------------------------------------------------------------------+
double CPositionInfo::StopLoss(void) const
  {
   return(PositionGetDouble(POSITION_SL));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_TP"                             |
//+------------------------------------------------------------------+
double CPositionInfo::TakeProfit(void) const
  {
   return(PositionGetDouble(POSITION_TP));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_PRICE_CURRENT"                  |
//+------------------------------------------------------------------+
double CPositionInfo::PriceCurrent(void) const
  {
   return(PositionGetDouble(POSITION_PRICE_CURRENT));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_COMMISSION"                     |
//+------------------------------------------------------------------+
double CPositionInfo::Commission(void) const
  {
//--- property POSITION_COMMISSION is deprecated
   SetUserError(ERR_FUNCTION_NOT_ALLOWED);
   return(0);
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_SWAP"                           |
//+------------------------------------------------------------------+
double CPositionInfo::Swap(void) const
  {
   return(PositionGetDouble(POSITION_SWAP));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_PROFIT"                         |
//+------------------------------------------------------------------+
double CPositionInfo::Profit(void) const
  {
   return(PositionGetDouble(POSITION_PROFIT));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_SYMBOL"                         |
//+------------------------------------------------------------------+
string CPositionInfo::Symbol(void) const
  {
   return(PositionGetString(POSITION_SYMBOL));
  }
//+------------------------------------------------------------------+
//| Get the property value "POSITION_COMMENT"                        |
//+------------------------------------------------------------------+
string CPositionInfo::Comment(void) const
  {
   return(PositionGetString(POSITION_COMMENT));
  }
//+------------------------------------------------------------------+
//| Access functions PositionGetInteger(...)                         |
//+------------------------------------------------------------------+
bool CPositionInfo::InfoInteger(const ENUM_POSITION_PROPERTY_INTEGER prop_id,long &var) const
  {
   return(PositionGetInteger(prop_id,var));
  }
//+------------------------------------------------------------------+
//| Access functions PositionGetDouble(...)                          |
//+------------------------------------------------------------------+
bool CPositionInfo::InfoDouble(const ENUM_POSITION_PROPERTY_DOUBLE prop_id,double &var) const
  {
   return(PositionGetDouble(prop_id,var));
  }
//+------------------------------------------------------------------+
//| Access functions PositionGetString(...)                          |
//+------------------------------------------------------------------+
bool CPositionInfo::InfoString(const ENUM_POSITION_PROPERTY_STRING prop_id,string &var) const
  {
   return(PositionGetString(prop_id,var));
  }
//+------------------------------------------------------------------+
//| Converts the position type to text                               |
//+------------------------------------------------------------------+
string CPositionInfo::FormatType(string &str,const uint type) const
  {
//--- see the type
   switch(type)
     {
      case POSITION_TYPE_BUY:
         str="buy";
         break;
      case POSITION_TYPE_SELL:
         str="sell";
         break;
      default:
         str="unknown position type "+(string)type;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Converts the position parameters to text                         |
//+------------------------------------------------------------------+
string CPositionInfo::FormatPosition(string &str) const
  {
   string tmp,type;
   long   tmp_long;
   ENUM_ACCOUNT_MARGIN_MODE margin_mode=(ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
//--- set up
   string symbol_name=this.Symbol();
   int    digits=_Digits;
   if(SymbolInfoInteger(symbol_name,SYMBOL_DIGITS,tmp_long))
      digits=(int)tmp_long;
//--- form the position description
   if(margin_mode==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      str=StringFormat("#%I64u %s %s %s %s",
                       Ticket(),
                       FormatType(type,PositionType()),
                       DoubleToString(Volume(),2),
                       symbol_name,
                       DoubleToString(PriceOpen(),digits+3));
   else
      str=StringFormat("%s %s %s %s",
                       FormatType(type,PositionType()),
                       DoubleToString(Volume(),2),
                       symbol_name,
                       DoubleToString(PriceOpen(),digits+3));
//--- add stops if there are any
   double sl=StopLoss();
   double tp=TakeProfit();
   if(sl!=0.0)
     {
      tmp=StringFormat(" sl: %s",DoubleToString(sl,digits));
      str+=tmp;
     }
   if(tp!=0.0)
     {
      tmp=StringFormat(" tp: %s",DoubleToString(tp,digits));
      str+=tmp;
     }
//--- return the result
   return(str);
  }
//+------------------------------------------------------------------+
//| Access functions PositionSelect(...)                             |
//+------------------------------------------------------------------+
bool CPositionInfo::Select(const string symbol)
  {
   return(PositionSelect(symbol));
  }
//+------------------------------------------------------------------+
//| Access functions PositionSelect(...)                             |
//+------------------------------------------------------------------+
bool CPositionInfo::SelectByMagic(const string symbol,const ulong magic)
  {
   bool res=false;
   uint total=PositionsTotal();
//---
   for(uint i=0; i<total; i++)
     {
      string position_symbol=PositionGetSymbol(i);
      if(position_symbol==symbol && magic==PositionGetInteger(POSITION_MAGIC))
        {
         res=true;
         break;
        }
     }
//---
   return(res);
  }
//+------------------------------------------------------------------+
//| Access functions PositionSelectByTicket(...)                     |
//+------------------------------------------------------------------+
bool CPositionInfo::SelectByTicket(const ulong ticket)
  {
   return(PositionSelectByTicket(ticket));
  }
//+------------------------------------------------------------------+
//| Select a position on the index                                   |
//+------------------------------------------------------------------+
bool CPositionInfo::SelectByIndex(const int index)
  {
   ulong ticket=PositionGetTicket(index);
   return(ticket>0);
  }
//+------------------------------------------------------------------+
//| Stored position's current state                                  |
//+------------------------------------------------------------------+
void CPositionInfo::StoreState(void)
  {
   m_type       =PositionType();
   m_volume     =Volume();
   m_price      =PriceOpen();
   m_stop_loss  =StopLoss();
   m_take_profit=TakeProfit();
  }
//+------------------------------------------------------------------+
//| Check position change                                            |
//+------------------------------------------------------------------+
bool CPositionInfo::CheckState(void)
  {
   if(m_type==PositionType()  &&
      m_volume==Volume()      &&
      m_price==PriceOpen()    &&
      m_stop_loss==StopLoss() &&
      m_take_profit==TakeProfit())
      return(false);
//---
   return(true);
  }
//+------------------------------------------------------------------+

//--- END INLINE: PositionInfo.mqh ---
//--- INLINE: AccountInfo.mqh ---
//+------------------------------------------------------------------+
//|                                                  AccountInfo.mqh |
//|                             Copyright 2000-2026, MetaQuotes Ltd. |
//|                                                     www.mql5.com |
//+------------------------------------------------------------------+
//--- INLINE: Object.mqh ---
//+------------------------------------------------------------------+
//|                                                       Object.mqh |
//|                             Copyright 2000-2026, MetaQuotes Ltd. |
//|                                                     www.mql5.com |
//+------------------------------------------------------------------+
//--- INLINE: StdLibErr.mqh ---
//+------------------------------------------------------------------+
//|                                                    StdLibErr.mqh |
//|                             Copyright 2000-2026, MetaQuotes Ltd. |
//|                                                     www.mql5.com |
//+------------------------------------------------------------------+
#define ERR_USER_INVALID_HANDLE                            1
#define ERR_USER_INVALID_BUFF_NUM                          2
#define ERR_USER_ITEM_NOT_FOUND                            3
#define ERR_USER_ARRAY_IS_EMPTY                            1000
//+------------------------------------------------------------------+

//--- END INLINE: StdLibErr.mqh ---
//+------------------------------------------------------------------+
//| Class CObject.                                                   |
//| Purpose: Base class for storing elements.                        |
//+------------------------------------------------------------------+
class CObject
  {
private:
   CObject          *m_prev;               // previous item of list
   CObject          *m_next;               // next item of list

public:
                     CObject(void): m_prev(NULL),m_next(NULL)            {                 }
                    ~CObject(void)                                       {                 }
   //--- methods to access protected data
   CObject          *Prev(void)                                    const { return(m_prev); }
   void              Prev(CObject *node)                                 { m_prev=node;    }
   CObject          *Next(void)                                    const { return(m_next); }
   void              Next(CObject *node)                                 { m_next=node;    }
   //--- methods for working with files
   virtual bool      Save(const int file_handle)                         { return(true);   }
   virtual bool      Load(const int file_handle)                         { return(true);   }
   //--- method of identifying the object
   virtual int       Type(void)                                    const { return(0);      }
   //--- method of comparing the objects
   virtual int       Compare(const CObject *node,const int mode=0) const { return(0);      }
  };
//+------------------------------------------------------------------+

//--- END INLINE: Object.mqh ---
//+------------------------------------------------------------------+
//| Class CAccountInfo.                                              |
//| Appointment: Class for access to account info.                   |
//|              Derives from class CObject.                         |
//+------------------------------------------------------------------+
class CAccountInfo : public CObject
  {
public:
                     CAccountInfo(void);
                    ~CAccountInfo(void);
   //--- fast access methods to the integer account propertyes
   long              Login(void) const;
   ENUM_ACCOUNT_TRADE_MODE TradeMode(void) const;
   string            TradeModeDescription(void) const;
   long              Leverage(void) const;
   ENUM_ACCOUNT_STOPOUT_MODE StopoutMode(void) const;
   string            StopoutModeDescription(void) const;
   ENUM_ACCOUNT_MARGIN_MODE MarginMode(void) const;
   string            MarginModeDescription(void) const;
   bool              TradeAllowed(void) const;
   bool              TradeExpert(void) const;
   int               LimitOrders(void) const;
   //--- fast access methods to the double account propertyes
   double            Balance(void) const;
   double            Credit(void) const;
   double            Profit(void) const;
   double            Equity(void) const;
   double            Margin(void) const;
   double            FreeMargin(void) const;
   double            MarginLevel(void) const;
   double            MarginCall(void) const;
   double            MarginStopOut(void) const;
   //--- fast access methods to the string account propertyes
   string            Name(void) const;
   string            Server(void) const;
   string            Currency(void) const;
   string            Company(void) const;
   //--- access methods to the API MQL5 functions
   long              InfoInteger(const ENUM_ACCOUNT_INFO_INTEGER prop_id) const;
   double            InfoDouble(const ENUM_ACCOUNT_INFO_DOUBLE prop_id) const;
   string            InfoString(const ENUM_ACCOUNT_INFO_STRING prop_id) const;
   //--- checks
   double            OrderProfitCheck(const string symbol,const ENUM_ORDER_TYPE trade_operation,
                                      const double volume,const double price_open,const double price_close) const;
   double            MarginCheck(const string symbol,const ENUM_ORDER_TYPE trade_operation,
                                 const double volume,const double price) const;
   double            FreeMarginCheck(const string symbol,const ENUM_ORDER_TYPE trade_operation,
                                     const double volume,const double price) const;
   double            MaxLotCheck(const string symbol,const ENUM_ORDER_TYPE trade_operation,
                                 const double price,const double percent=100) const;
  };
//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CAccountInfo::CAccountInfo(void)
  {
  }
//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CAccountInfo::~CAccountInfo(void)
  {
  }
//+------------------------------------------------------------------+
//| Get the property value "ACCOUNT_LOGIN"                           |
//+------------------------------------------------------------------+
long CAccountInfo::Login(void) const
  {
   return(AccountInfoInteger(ACCOUNT_LOGIN));
  }
//+------------------------------------------------------------------+
//| Get the property value "ACCOUNT_TRADE_MODE"                      |
//+------------------------------------------------------------------+
ENUM_ACCOUNT_TRADE_MODE CAccountInfo::TradeMode(void) const
  {
   return((ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE));
  }
//+------------------------------------------------------------------+
//| Get the property value "ACCOUNT_TRADE_MODE" as string            |
//+------------------------------------------------------------------+
string CAccountInfo::TradeModeDescription(void) const
  {
   string str;
//---
   switch(TradeMode())
     {
      case ACCOUNT_TRADE_MODE_DEMO:
         str="Demo trading account";
         break;
      case ACCOUNT_TRADE_MODE_CONTEST:
         str="Contest trading account";
         break;
      case ACCOUNT_TRADE_MODE_REAL:
         str="Real trading account";
         break;
      default:
         str="Unknown trade account";
     }
//---
   return(str);
  }
//+------------------------------------------------------------------+
//| Get the property value "ACCOUNT_LEVERAGE"                        |
//+------------------------------------------------------------------+
long CAccountInfo::Leverage(void) const
  {
   return(AccountInfoInteger(ACCOUNT_LEVERAGE));
  }
//+------------------------------------------------------------------+
//| Get the property value "ACCOUNT_MARGIN_SO_MODE"                  |
//+------------------------------------------------------------------+
ENUM_ACCOUNT_STOPOUT_MODE CAccountInfo::StopoutMode(void) const
  {
   return((ENUM_ACCOUNT_STOPOUT_MODE)AccountInfoInteger(ACCOUNT_MARGIN_SO_MODE));
  }
//+------------------------------------------------------------------+
//| Get the property value "ACCOUNT_MARGIN_SO_MODE" as string        |
//+------------------------------------------------------------------+
string CAccountInfo::StopoutModeDescription(void) const
  {
   string str;
//---
   switch(StopoutMode())
     {
      case ACCOUNT_STOPOUT_MODE_PERCENT:
         str="Level is specified in percentage";
         break;
      case ACCOUNT_STOPOUT_MODE_MONEY:
         str="Level is specified in money";
         break;
      default:
         str="Unknown stopout mode";
     }
//---
   return(str);
  }
//+------------------------------------------------------------------+
//| Get the property value "ACCOUNT_MARGIN_MODE"                     |
//+------------------------------------------------------------------+
ENUM_ACCOUNT_MARGIN_MODE CAccountInfo::MarginMode(void) const
  {
   return((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE));
  }
//+------------------------------------------------------------------+
//| Get the property value "ACCOUNT_MARGIN_MODE" as string           |
//+------------------------------------------------------------------+
string CAccountInfo::MarginModeDescription(void) const
  {
   string str;
//---
   switch(MarginMode())
     {
      case ACCOUNT_MARGIN_MODE_RETAIL_NETTING:
         str="Netting";
         break;
      case ACCOUNT_MARGIN_MODE_EXCHANGE:
         str="Exchange";
         break;
      case ACCOUNT_MARGIN_MODE_RETAIL_HEDGING:
         str="Hedging";
         break;
      default:
         str="Unknown margin mode";
     }
//---
   return(str);
  }
//+------------------------------------------------------------------+
//| Get the property value "ACCOUNT_TRADE_ALLOWED"                   |
//+------------------------------------------------------------------+
bool CAccountInfo::TradeAllowed(void) const
  {
   return((bool)AccountInfoInteger(ACCOUNT_TRADE_ALLOWED));
  }
//+------------------------------------------------------------------+
//| Get the property value "ACCOUNT_TRADE_EXPERT"                    |
//+------------------------------------------------------------------+
bool CAccountInfo::TradeExpert(void) const
  {
   return((bool)AccountInfoInteger(ACCOUNT_TRADE_EXPERT));
  }
//+------------------------------------------------------------------+
//| Get the property value "ACCOUNT_LIMIT_ORDERS"                    |
//+------------------------------------------------------------------+
int CAccountInfo::LimitOrders(void) const
  {
   return((int)AccountInfoInteger(ACCOUNT_LIMIT_ORDERS));
  }
//+------------------------------------------------------------------+
//| Get the property value "ACCOUNT_BALANCE"                         |
//+------------------------------------------------------------------+
double CAccountInfo::Balance(void) const
  {
   return(AccountInfoDouble(ACCOUNT_BALANCE));
  }
//+------------------------------------------------------------------+
//| Get the property value "ACCOUNT_CREDIT"                          |
//+------------------------------------------------------------------+
double CAccountInfo::Credit(void) const
  {
   return(AccountInfoDouble(ACCOUNT_CREDIT));
  }
//+------------------------------------------------------------------+
//| Get the property value "ACCOUNT_PROFIT"                          |
//+------------------------------------------------------------------+
double CAccountInfo::Profit(void) const
  {
   return(AccountInfoDouble(ACCOUNT_PROFIT));
  }
//+------------------------------------------------------------------+
//| Get the property value "ACCOUNT_EQUITY"                          |
//+------------------------------------------------------------------+
double CAccountInfo::Equity(void) const
  {
   return(AccountInfoDouble(ACCOUNT_EQUITY));
  }
//+------------------------------------------------------------------+
//| Get the property value "ACCOUNT_MARGIN"                          |
//+------------------------------------------------------------------+
double CAccountInfo::Margin(void) const
  {
   return(AccountInfoDouble(ACCOUNT_MARGIN));
  }
//+------------------------------------------------------------------+
//| Get the property value "ACCOUNT_MARGIN_FREE"                     |
//+------------------------------------------------------------------+
double CAccountInfo::FreeMargin(void) const
  {
   return(AccountInfoDouble(ACCOUNT_MARGIN_FREE));
  }
//+------------------------------------------------------------------+
//| Get the property value "ACCOUNT_MARGIN_LEVEL"                    |
//+------------------------------------------------------------------+
double CAccountInfo::MarginLevel(void) const
  {
   return(AccountInfoDouble(ACCOUNT_MARGIN_LEVEL));
  }
//+------------------------------------------------------------------+
//| Get the property value "ACCOUNT_MARGIN_SO_CALL"                  |
//+------------------------------------------------------------------+
double CAccountInfo::MarginCall(void) const
  {
   return(AccountInfoDouble(ACCOUNT_MARGIN_SO_CALL));
  }
//+------------------------------------------------------------------+
//| Get the property value "ACCOUNT_MARGIN_SO_SO"                    |
//+------------------------------------------------------------------+
double CAccountInfo::MarginStopOut(void) const
  {
   return(AccountInfoDouble(ACCOUNT_MARGIN_SO_SO));
  }
//+------------------------------------------------------------------+
//| Get the property value "ACCOUNT_NAME"                            |
//+------------------------------------------------------------------+
string CAccountInfo::Name(void) const
  {
   return(AccountInfoString(ACCOUNT_NAME));
  }
//+------------------------------------------------------------------+
//| Get the property value "ACCOUNT_SERVER"                          |
//+------------------------------------------------------------------+
string CAccountInfo::Server(void) const
  {
   return(AccountInfoString(ACCOUNT_SERVER));
  }
//+------------------------------------------------------------------+
//| Get the property value "ACCOUNT_CURRENCY"                        |
//+------------------------------------------------------------------+
string CAccountInfo::Currency(void) const
  {
   return(AccountInfoString(ACCOUNT_CURRENCY));
  }
//+------------------------------------------------------------------+
//| Get the property value "ACCOUNT_COMPANY"                         |
//+------------------------------------------------------------------+
string CAccountInfo::Company(void) const
  {
   return(AccountInfoString(ACCOUNT_COMPANY));
  }
//+------------------------------------------------------------------+
//| Access functions AccountInfoInteger(...)                         |
//+------------------------------------------------------------------+
long CAccountInfo::InfoInteger(const ENUM_ACCOUNT_INFO_INTEGER prop_id) const
  {
   return(AccountInfoInteger(prop_id));
  }
//+------------------------------------------------------------------+
//| Access functions AccountInfoDouble(...)                          |
//+------------------------------------------------------------------+
double CAccountInfo::InfoDouble(const ENUM_ACCOUNT_INFO_DOUBLE prop_id) const
  {
   return(AccountInfoDouble(prop_id));
  }
//+------------------------------------------------------------------+
//| Access functions AccountInfoString(...)                          |
//+------------------------------------------------------------------+
string CAccountInfo::InfoString(const ENUM_ACCOUNT_INFO_STRING prop_id) const
  {
   return(AccountInfoString(prop_id));
  }
//+------------------------------------------------------------------+
//| Access functions OrderCalcProfit(...).                            |
//| INPUT:  name            - symbol name,                           |
//|         trade_operation - trade operation,                       |
//|         volume          - volume of the opening position,        |
//|         price_open      - price of the opening position,         |
//|         price_close     - price of the closing position.         |
//+------------------------------------------------------------------+
double CAccountInfo::OrderProfitCheck(const string symbol,const ENUM_ORDER_TYPE trade_operation,
                                      const double volume,const double price_open,const double price_close) const
  {
   double profit=EMPTY_VALUE;
//---
   if(!OrderCalcProfit(trade_operation,symbol,volume,price_open,price_close,profit))
      return(EMPTY_VALUE);
//---
   return(profit);
  }
//+------------------------------------------------------------------+
//| Access functions OrderCalcMargin(...).                           |
//| INPUT:  name            - symbol name,                           |
//|         trade_operation - trade operation,                       |
//|         volume          - volume of the opening position,        |
//|         price           - price of the opening position.         |
//+------------------------------------------------------------------+
double CAccountInfo::MarginCheck(const string symbol,const ENUM_ORDER_TYPE trade_operation,
                                 const double volume,const double price) const
  {
   double margin=EMPTY_VALUE;
//---
   if(!OrderCalcMargin(trade_operation,symbol,volume,price,margin))
      return(EMPTY_VALUE);
//---
   return(margin);
  }
//+------------------------------------------------------------------+
//| Access functions OrderCalcMargin(...).                           |
//| INPUT:  name            - symbol name,                           |
//|         trade_operation - trade operation,                       |
//|         volume          - volume of the opening position,        |
//|         price           - price of the opening position.         |
//+------------------------------------------------------------------+
double CAccountInfo::FreeMarginCheck(const string symbol,const ENUM_ORDER_TYPE trade_operation,
                                     const double volume,const double price) const
  {
   return(FreeMargin()-MarginCheck(symbol,trade_operation,volume,price));
  }
//+------------------------------------------------------------------+
//| Access functions OrderCalcMargin(...).                           |
//| INPUT:  name            - symbol name,                           |
//|         trade_operation - trade operation,                       |
//|         price           - price of the opening position,         |
//|         percent         - percent of available margin [1-100%].   |
//+------------------------------------------------------------------+
double CAccountInfo::MaxLotCheck(const string symbol,const ENUM_ORDER_TYPE trade_operation,
                                 const double price,const double percent) const
  {
   double margin=0.0;
//--- checks
   if(symbol=="" || price<=0.0 || percent<1 || percent>100)
     {
      Print("CAccountInfo::MaxLotCheck invalid parameters");
      return(0.0);
     }
//--- calculate margin requirements for 1 lot
   if(!OrderCalcMargin(trade_operation,symbol,1.0,price,margin) || margin<0.0)
     {
      Print("CAccountInfo::MaxLotCheck margin calculation failed");
      return(0.0);
     }
//---
   if(margin==0.0) // for pending orders
      return(SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX));
//--- calculate maximum volume
   double volume=NormalizeDouble(FreeMargin()*percent/100.0/margin,2);
//--- normalize and check limits
   double stepvol=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   if(stepvol>0.0)
      volume=stepvol*MathFloor(volume/stepvol);
//---
   double minvol=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   if(volume<minvol)
      volume=0.0;
//---
   double maxvol=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
   if(volume>maxvol)
      volume=maxvol;
//--- return volume
   return(volume);
  }
//+------------------------------------------------------------------+

//--- END INLINE: AccountInfo.mqh ---
//--- INLINE: FixedRangeVolumeProfile.mqh ---
//+------------------------------------------------------------------+
//|                                  FixedRangeVolumeProfile.mqh      |
//|                          Fixed Range Volume Profile Engine        |
//|                          Computes POC / VAH / VAL / LVN zones     |
//|                          from bar-level volume distribution        |
//+------------------------------------------------------------------+
#ifndef FIXED_RANGE_VOLUME_PROFILE_MQH
#define FIXED_RANGE_VOLUME_PROFILE_MQH

//--- Maximum number of volume profile zones
#define FRVP_MAX_ZONES 50

//+------------------------------------------------------------------+
//| Volume node (single price bucket)                                |
//+------------------------------------------------------------------+
struct FRVPNode
{
   double      priceLow;       // bucket lower boundary
   double      priceHigh;      // bucket upper boundary
   double      priceMid;       // bucket mid price
   long        volume;         // cumulative volume in this bucket
   bool        isPOC;          // point of control (highest volume)
   bool        isVAH;          // value area high boundary
   bool        isVAL;          // value area low boundary
   bool        isLVN;          // low volume node (thin area)
};

//+------------------------------------------------------------------+
//| FRVP zone (grouped levels for trading)                           |
//+------------------------------------------------------------------+
enum FRVPZoneType
{
   FRVP_POC,       // Point of Control — max volume
   FRVP_VAH,       // Value Area High — 70% volume upper
   FRVP_VAL,       // Value Area Low — 70% volume lower
   FRVP_HVN,       // High Volume Node — thick liquidity
   FRVP_LVN        // Low Volume Node — thin / rejection zone
};

struct FRVPZone
{
   FRVPZoneType  type;
   double        price;          // zone center price
   double        upper;          // zone upper boundary
   double        lower;          // zone lower boundary
   long          volume;         // volume at this zone
   double        strength;       // 0..1 relative strength vs POC
};

//+------------------------------------------------------------------+
//| FRVP computation result                                          |
//+------------------------------------------------------------------+
struct FRVPResult
{
   double        poc;            // point of control price
   double        vah;            // value area high
   double        val;            // value area low
   double        rangeHigh;      // profile range high
   double        rangeLow;       // profile range low
   long          totalVolume;    // total volume in range
   FRVPZone      zones[];        // tradeable zones
   int           zoneCount;      // number of zones
   bool          valid;          // computation succeeded
};

//+------------------------------------------------------------------+
//| Volume Profile State (persistent per EA instance)                |
//+------------------------------------------------------------------+
struct FRVPState
{
   FRVPResult    current;        // latest computed profile
   datetime      lastCompute;    // when profile was last updated
   int           computeBar;     // which bar index was the anchor
};

//+------------------------------------------------------------------+
//| FRVP: Compute volume profile from bar data                       |
//|                                                                  |
//| anchors  = number of recent bars to profile (the "fixed range") |
//| bucketPips = price range per bucket (in price units, e.g. 0.50  |
//|              for gold = 50 cents, or 0.00050 for EURUSD = 5 pips)|
//| valueAreaPct = volume % to include in value area (default 70)   |
//| hvnThreshold = % of POC volume to qualify as HVN (default 0.7) |
//| lvnThreshold = % of POC volume below which is LVN (default 0.2) |
//+------------------------------------------------------------------+
bool FRVP_Compute(FRVPState &state, string symbol, ENUM_TIMEFRAMES tf,
                  int anchors, double bucketPips, double valueAreaPct = 70.0,
                  double hvnThreshold = 0.7, double lvnThreshold = 0.2)
{
   //--- Fetch OHLCV data
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(symbol, tf, 0, anchors + 1, rates) < anchors + 1)
      return false;

   //--- Find range high/low over the anchor period
   double rangeHigh = -DBL_MAX;
   double rangeLow  =  DBL_MAX;
   long   totalVol  = 0;

   for(int i = 0; i < anchors; i++)
   {
      if(rates[i].high > rangeHigh) rangeHigh = rates[i].high;
      if(rates[i].low  < rangeLow)  rangeLow  = rates[i].low;
      totalVol += rates[i].tick_volume;
   }

   if(rangeHigh <= rangeLow || totalVol <= 0) return false;

   //--- Determine number of buckets
   double rangeSize = rangeHigh - rangeLow;
   int numBuckets = (int)MathCeil(rangeSize / bucketPips);
   if(numBuckets < 3)  numBuckets = 3;
   if(numBuckets > 100) numBuckets = 100;

   double bucketSize = rangeSize / numBuckets;

   //--- Build volume distribution
   long bucketVol[];
   ArrayResize(bucketVol, numBuckets);
   ArrayInitialize(bucketVol, 0);

   for(int i = 0; i < anchors; i++)
   {
      double barLow  = rates[i].low;
      double barHigh = rates[i].high;
      long   barVol  = rates[i].tick_volume;

      //--- Distribute volume across buckets this bar touches
      int loIdx = (int)((barLow - rangeLow) / bucketSize);
      int hiIdx = (int)((barHigh - rangeLow) / bucketSize);
      if(loIdx < 0) loIdx = 0;
      if(hiIdx >= numBuckets) hiIdx = numBuckets - 1;

      int touched = hiIdx - loIdx + 1;
      if(touched <= 0) touched = 1;
      long volPerBucket = barVol / touched;
      if(volPerBucket <= 0) volPerBucket = barVol; // at least 1 tick

      for(int b = loIdx; b <= hiIdx; b++)
         bucketVol[b] += volPerBucket;
   }

   //--- Find POC (highest volume bucket)
   int pocIdx = 0;
   long maxVol = 0;
   for(int b = 0; b < numBuckets; b++)
   {
      if(bucketVol[b] > maxVol)
      {
         maxVol = bucketVol[b];
         pocIdx = b;
      }
   }

   double pocPrice = rangeLow + (pocIdx + 0.5) * bucketSize;

   //--- Compute Value Area (expand outward from POC until ~70% of total volume)
   long   vaVolTarget = (long)(totalVol * valueAreaPct / 100.0);
   long   vaVolAccum  = bucketVol[pocIdx];
   int    vaLoIdx     = pocIdx;
   int    vaHiIdx     = pocIdx;

   while(vaVolAccum < vaVolTarget)
   {
      //--- Expand to the side with more volume
      long volBelow = (vaLoIdx > 0) ? bucketVol[vaLoIdx - 1] : 0;
      long volAbove = (vaHiIdx < numBuckets - 1) ? bucketVol[vaHiIdx + 1] : 0;

      if(volBelow == 0 && volAbove == 0) break;

      if(volBelow >= volAbove && vaLoIdx > 0)
      {
         vaLoIdx--;
         vaVolAccum += bucketVol[vaLoIdx];
      }
      else if(vaHiIdx < numBuckets - 1)
      {
         vaHiIdx++;
         vaVolAccum += bucketVol[vaHiIdx];
      }
      else if(vaLoIdx > 0)
      {
         vaLoIdx--;
         vaVolAccum += bucketVol[vaLoIdx];
      }
      else break;
   }

   double vahPrice = rangeLow + (vaHiIdx + 1) * bucketSize;
   double valPrice = rangeLow + vaLoIdx * bucketSize;

   //--- Fill result
   state.current.poc         = pocPrice;
   state.current.vah         = vahPrice;
   state.current.val         = valPrice;
   state.current.rangeHigh   = rangeHigh;
   state.current.rangeLow    = rangeLow;
   state.current.totalVolume = totalVol;
   state.current.valid       = true;
   state.current.zoneCount   = 0;

   //--- Build zones: POC, VAH, VAL, then scan for HVN and LVN
   ArrayResize(state.current.zones, FRVP_MAX_ZONES);

   // POC zone
   state.current.zones[0].type     = FRVP_POC;
   state.current.zones[0].price    = pocPrice;
   state.current.zones[0].upper    = pocPrice + bucketSize * 0.5;
   state.current.zones[0].lower    = pocPrice - bucketSize * 0.5;
   state.current.zones[0].volume   = maxVol;
   state.current.zones[0].strength = 1.0;

   // VAH zone
   state.current.zones[1].type     = FRVP_VAH;
   state.current.zones[1].price    = vahPrice;
   state.current.zones[1].upper    = vahPrice + bucketSize * 0.5;
   state.current.zones[1].lower    = vahPrice - bucketSize * 0.5;
   state.current.zones[1].volume   = (vaHiIdx >= 0 && vaHiIdx < numBuckets) ? bucketVol[vaHiIdx] : 0;
   state.current.zones[1].strength = (maxVol > 0) ? (double)state.current.zones[1].volume / maxVol : 0;

   // VAL zone
   state.current.zones[2].type     = FRVP_VAL;
   state.current.zones[2].price    = valPrice;
   state.current.zones[2].upper    = valPrice + bucketSize * 0.5;
   state.current.zones[2].lower    = valPrice - bucketSize * 0.5;
   state.current.zones[2].volume   = (vaLoIdx >= 0 && vaLoIdx < numBuckets) ? bucketVol[vaLoIdx] : 0;
   state.current.zones[2].strength = (maxVol > 0) ? (double)state.current.zones[2].volume / maxVol : 0;

   int zoneIdx = 3;

   //--- Scan for HVN and LVN nodes (excluding POC region)
   for(int b = 0; b < numBuckets && zoneIdx < FRVP_MAX_ZONES; b++)
   {
      // Skip POC bucket and VA interior
      if(b == pocIdx) continue;
      if(b >= vaLoIdx && b <= vaHiIdx) continue;

      double strength = (maxVol > 0) ? (double)bucketVol[b] / maxVol : 0;

      if(strength >= hvnThreshold)
      {
         // High Volume Node — strong support/resistance
         state.current.zones[zoneIdx].type     = FRVP_HVN;
         state.current.zones[zoneIdx].price    = rangeLow + (b + 0.5) * bucketSize;
         state.current.zones[zoneIdx].upper    = rangeLow + (b + 1) * bucketSize;
         state.current.zones[zoneIdx].lower    = rangeLow + b * bucketSize;
         state.current.zones[zoneIdx].volume   = bucketVol[b];
         state.current.zones[zoneIdx].strength = strength;
         zoneIdx++;
      }
      else if(strength <= lvnThreshold && bucketVol[b] > 0)
      {
         // Low Volume Node — price tends to reject / move through quickly
         state.current.zones[zoneIdx].type     = FRVP_LVN;
         state.current.zones[zoneIdx].price    = rangeLow + (b + 0.5) * bucketSize;
         state.current.zones[zoneIdx].upper    = rangeLow + (b + 1) * bucketSize;
         state.current.zones[zoneIdx].lower    = rangeLow + b * bucketSize;
         state.current.zones[zoneIdx].volume   = bucketVol[b];
         state.current.zones[zoneIdx].strength = strength;
         zoneIdx++;
      }
   }

   state.current.zoneCount = zoneIdx;
   state.lastCompute = rates[0].time;
   state.computeBar  = anchors;

   return true;
}

//+------------------------------------------------------------------+
//| FRVP: Check if price is at a specific zone type                  |
//| Returns the zone index if within tolerance, -1 otherwise         |
//+------------------------------------------------------------------+
int FRVP_AtZone(FRVPResult &profile, double price, FRVPZoneType type, double tolerance)
{
   for(int i = 0; i < profile.zoneCount; i++)
   {
      if(profile.zones[i].type != type) continue;
      if(MathAbs(price - profile.zones[i].price) <= tolerance)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
//| FRVP: Check if price is above/below value area                  |
//| Returns +1 if above VAH, -1 if below VAL, 0 if inside VA       |
//+------------------------------------------------------------------+
int FRVP_RelativeToVA(FRVPResult &profile, double price)
{
   if(!profile.valid) return 0;
   if(price > profile.vah) return +1;
   if(price < profile.val) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| FRVP: Distance from POC as fraction of profile range            |
//+------------------------------------------------------------------+
double FRVP_POCDistance(FRVPResult &profile, double price)
{
   if(!profile.valid || profile.rangeHigh <= profile.rangeLow) return 0;
   return (price - profile.poc) / (profile.rangeHigh - profile.rangeLow);
}

//+------------------------------------------------------------------+
//| FRVP: Find nearest zone to price (any type)                     |
//| Returns distance in price units                                  |
//+------------------------------------------------------------------+
double FRVP_NearestZoneDistance(FRVPResult &profile, double price)
{
   if(!profile.valid || profile.zoneCount == 0) return DBL_MAX;
   double minDist = DBL_MAX;
   for(int i = 0; i < profile.zoneCount; i++)
   {
      double dist = MathAbs(price - profile.zones[i].price);
      if(dist < minDist) minDist = dist;
   }
   return minDist;
}

//+------------------------------------------------------------------+
//| FRVP: Get nearest zone (any type) — returns zone index or -1    |
//+------------------------------------------------------------------+
int FRVP_NearestZone(FRVPResult &profile, double price)
{
   if(!profile.valid || profile.zoneCount == 0) return -1;
   double minDist = DBL_MAX;
   int    nearest = -1;
   for(int i = 0; i < profile.zoneCount; i++)
   {
      double dist = MathAbs(price - profile.zones[i].price);
      if(dist < minDist)
      {
         minDist = dist;
         nearest = i;
      }
   }
   return nearest;
}

//+------------------------------------------------------------------+
//| FRVP: Is price at POC?                                           |
//+------------------------------------------------------------------+
bool FRVP_AtPOC(FRVPResult &profile, double price, double tolerance)
{
   return FRVP_AtZone(profile, price, FRVP_POC, tolerance) >= 0;
}

//+------------------------------------------------------------------+
//| FRVP: Is price at VAH (resistance)?                              |
//+------------------------------------------------------------------+
bool FRVP_AtVAH(FRVPResult &profile, double price, double tolerance)
{
   return FRVP_AtZone(profile, price, FRVP_VAH, tolerance) >= 0;
}

//+------------------------------------------------------------------+
//| FRVP: Is price at VAL (support)?                                 |
//+------------------------------------------------------------------+
bool FRVP_AtVAL(FRVPResult &profile, double price, double tolerance)
{
   return FRVP_AtZone(profile, price, FRVP_VAL, tolerance) >= 0;
}

//+------------------------------------------------------------------+
//| FRVP: Is there an HVN nearby?                                    |
//+------------------------------------------------------------------+
int FRVP_NearHVN(FRVPResult &profile, double price, double tolerance)
{
   return FRVP_AtZone(profile, price, FRVP_HVN, tolerance);
}

//+------------------------------------------------------------------+
//| FRVP: Is there an LVN nearby?                                    |
//+------------------------------------------------------------------+
int FRVP_NearLVN(FRVPResult &profile, double price, double tolerance)
{
   return FRVP_AtZone(profile, price, FRVP_LVN, tolerance);
}

//+------------------------------------------------------------------+
//| FRVP: Get zone name string for logging                           |
//+------------------------------------------------------------------+
string FRVP_ZoneName(FRVPZoneType type)
{
   switch(type)
   {
      case FRVP_POC: return "POC";
      case FRVP_VAH: return "VAH";
      case FRVP_VAL: return "VAL";
      case FRVP_HVN: return "HVN";
      case FRVP_LVN: return "LVN";
   }
   return "???";
}

//+------------------------------------------------------------------+
//| FRVP: Print profile summary for debugging                        |
//+------------------------------------------------------------------+
void FRVP_PrintProfile(FRVPResult &profile, string symbol)
{
   if(!profile.valid)
   {
      Print(symbol, " FRVP: no valid profile");
      return;
   }
   Print(symbol, " FRVP | POC=", DoubleToString(profile.poc, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)),
         " VAH=", DoubleToString(profile.vah, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)),
         " VAL=", DoubleToString(profile.val, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)),
         " Range=[", DoubleToString(profile.rangeLow, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)),
         " .. ", DoubleToString(profile.rangeHigh, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)),
         "] Vol=", profile.totalVolume,
         " Zones=", profile.zoneCount);
}

#endif // FIXED_RANGE_VOLUME_PROFILE_MQH

//--- END INLINE: FixedRangeVolumeProfile.mqh ---
//--- INLINE: PriceActionPatterns.mqh ---
//+------------------------------------------------------------------+
//|                                        PriceActionPatterns.mqh    |
//|                          Enhanced Price Action Pattern Detection  |
//|                          Pin bar, Engulfing, Engulf, Inside Bar,  |
//|                          Pin+Engulf combo, OB flip, BOS/CHoCH    |
//+------------------------------------------------------------------+
#ifndef PRICE_ACTION_PATTERNS_MQH
#define PRICE_ACTION_PATTERNS_MQH

//+------------------------------------------------------------------+
//| Price action signal result                                       |
//+------------------------------------------------------------------+
struct PASignal
{
   int    direction;    // +1 = bullish, -1 = bearish, 0 = none
   int    strength;     // 0..4 quality score
   string patternName;  // human-readable
};

//+------------------------------------------------------------------+
//| Pin Bar Detection                                                |
//| Long wick = rejection. Bullish pin = long lower wick.            |
//| Bearish pin = long upper wick.                                   |
//+------------------------------------------------------------------+
PASignal PA_DetectPinBar(MqlRates &r1, MqlRates &r2, double atr,
                         double minWickATR = 0.5, double wickBodyRatio = 2.0)
{
   PASignal sig = {0, 0, ""};

   double body1   = MathAbs(r1.close - r1.open);
   double range1  = r1.high - r1.low;
   double lowerW  = MathMin(r1.close, r1.open) - r1.low;
   double upperW  = r1.high - MathMax(r1.close, r1.open);
   double body2   = MathAbs(r2.close - r2.open); // context bar

   if(atr <= 0 || range1 <= 0) return sig;

   //--- Bullish pin bar: long lower wick, small upper wick, close in upper third
   if(lowerW >= atr * minWickATR && lowerW >= body1 * wickBodyRatio
      && upperW < body1 * 0.5 && body1 > 0)
   {
      sig.direction = +1;
      sig.strength  = 3;
      sig.patternName = "PinBar_BULL";

      //--- Boost: pin at prior bar's low or lower (extra rejection)
      if(r1.low <= r2.low) { sig.strength = 4; sig.patternName = "PinBar_BULL+Low"; }
   }

   //--- Bearish pin bar: long upper wick, close in lower third
   if(upperW >= atr * minWickATR && upperW >= body1 * wickBodyRatio
      && lowerW < body1 * 0.5 && body1 > 0)
   {
      sig.direction = -1;
      sig.strength  = 3;
      sig.patternName = "PinBar_BEAR";

      if(r1.high >= r2.high) { sig.strength = 4; sig.patternName = "PinBar_BEAR+High"; }
   }

   return sig;
}

//+------------------------------------------------------------------+
//| Engulfing Pattern Detection                                      |
//| Bullish: prev bearish bar fully engulfed by current bullish bar. |
//| Bearish: prev bullish bar fully engulfed by current bearish bar. |
//+------------------------------------------------------------------+
PASignal PA_DetectEngulfing(MqlRates &r1, MqlRates &r2, double atr,
                            double minBodyATR = 0.15)
{
   PASignal sig = {0, 0, ""};

   double body1 = MathAbs(r1.close - r1.open);
   double body2 = MathAbs(r2.close - r2.open);
   bool   r1Bull = r1.close > r1.open;
   bool   r1Bear = r1.close < r1.open;
   bool   r2Bull = r2.close > r2.open;
   bool   r2Bear = r2.close < r2.open;

   if(atr <= 0) return sig;

   //--- Bullish engulfing: r2 bearish, r1 bullish, r1 body wraps r2 body
   if(r2Bear && r1Bull && body1 > body2 * 1.1 && body1 > atr * minBodyATR)
   {
      if(r1.close > r2.open && r1.open < r2.close)
      {
         sig.direction = +1;
         sig.strength  = 3;
         sig.patternName = "Engulf_BULL";

         //--- Boost: r1 also closes above r2 high (stronger conviction)
         if(r1.close > r2.high) { sig.strength = 4; sig.patternName = "Engulf_BULL+CloseAbove"; }
      }
   }

   //--- Bearish engulfing: r2 bullish, r1 bearish, r1 body wraps r2 body
   if(r2Bull && r1Bear && body1 > body2 * 1.1 && body1 > atr * minBodyATR)
   {
      if(r1.close < r2.open && r1.open > r2.close)
      {
         sig.direction = -1;
         sig.strength  = 3;
         sig.patternName = "Engulf_BEAR";

         if(r1.close < r2.low) { sig.strength = 4; sig.patternName = "Engulf_BEAR+CloseBelow"; }
      }
   }

   return sig;
}

//+------------------------------------------------------------------+
//| Inside Bar Detection                                             |
//| Current bar range fully inside previous bar range. Often a       |
//| consolidation before breakout.                                   |
//+------------------------------------------------------------------+
PASignal PA_DetectInsideBar(MqlRates &r1, MqlRates &r2, double atr)
{
   PASignal sig = {0, 0, ""};
   if(atr <= 0) return sig;

   //--- Inside bar: r1 high <= r2 high AND r1 low >= r2 low
   if(r1.high <= r2.high && r1.low >= r2.low)
   {
      //--- Direction determined by breakout context
      //--- Bullish inside bar: preceding trend was down, expecting reversal up
      if(r2.close < r2.open) // prev bar was bearish → potential bullish breakout
      {
         sig.direction = +1;
         sig.strength  = 2;
         sig.patternName = "InsideBar_BULL";
      }
      else
      {
         sig.direction = -1;
         sig.strength  = 2;
         sig.patternName = "InsideBar_BEAR";
      }
   }

   return sig;
}

//+------------------------------------------------------------------+
//| Pin + Engulf Combo                                               |
//| Pin bar followed by engulfing in same direction = strongest PA   |
//+------------------------------------------------------------------+
PASignal PA_DetectPinEngulfCombo(MqlRates &rates[], int count, double atr,
                                  double minWickATR = 0.5, double wickBodyRatio = 2.0,
                                  double minBodyATR = 0.15)
{
   PASignal sig = {0, 0, ""};
   if(count < 3 || atr <= 0) return sig;

   //--- rates[0]=newest (forming), [1]=last closed, [2]=older
   //--- Check: bar[2] = pin bar, bar[1] = engulfing confirmation
   PASignal pin = PA_DetectPinBar(rates[1], rates[2], atr, minWickATR, wickBodyRatio);
   PASignal eng = PA_DetectEngulfing(rates[1], rates[2], atr, minBodyATR);

   //--- Wait: pin is on [1] (older), engulf on [0] (newer)
   //--- Actually: r1=bar1 (last closed), r2=bar2 (one before)
   //--- So pin on bar2 + engulf from bar1→bar2
   //--- Better: check pin on bar[1] using bar[2] as context, then engulf on bar[0] using bar[1]
   PASignal pin1 = PA_DetectPinBar(rates[1], rates[2], atr, minWickATR, wickBodyRatio);
   PASignal eng0 = PA_DetectEngulfing(rates[0], rates[1], atr, minBodyATR);

   if(pin1.direction == +1 && eng0.direction == +1)
   {
      sig.direction = +1;
      sig.strength  = 4; // max strength
      sig.patternName = "PinEngulf_BULL";
   }
   else if(pin1.direction == -1 && eng0.direction == -1)
   {
      sig.direction = -1;
      sig.strength  = 4;
      sig.patternName = "PinEngulf_BEAR";
   }

   return sig;
}

//+------------------------------------------------------------------+
//| Three-Bar Reversal (Morning Star / Evening Star)                |
//| Bar1: large candle in trend direction                            |
//| Bar2: small body (indecision)                                   |
//| Bar3: large candle in reversal direction                         |
//+------------------------------------------------------------------+
PASignal PA_DetectThreeBarReversal(MqlRates &rates[], int count, double atr,
                                    double minBodyATR = 0.15)
{
   PASignal sig = {0, 0, ""};
   if(count < 3 || atr <= 0) return sig;

   //--- [2]=oldest, [1]=middle, [0]=newest (but we use last 3 closed: rates[1],rates[2],rates[3])
   //--- We'll use rates[1]=newest closed, [2]=middle, [3]=oldest
   //--- Actually: let's use [0]=forming (skip), [1]=newest closed, [2]=middle, [3]=oldest
   if(count < 4) return sig;

   double o0 = rates[1].open,  c0 = rates[1].close;  // newest closed
   double o1 = rates[2].open,  c1 = rates[2].close;  // middle
   double o2 = rates[3].open,  c2 = rates[3].close;  // oldest

   double body0 = MathAbs(c0 - o0);
   double body1 = MathAbs(c1 - o1);
   double body2 = MathAbs(c2 - o2);

   //--- Morning Star (bullish): bar2=big bearish, bar1=small body, bar0=big bullish
   if(c2 < o2 && c0 > o0) // bar2 bearish, bar0 bullish
   {
      if(body2 > atr * minBodyATR && body0 > atr * minBodyATR && body1 < body2 * 0.4)
      {
         sig.direction = +1;
         sig.strength  = 3;
         sig.patternName = "MorningStar";
         //--- Boost: bar0 closes above midpoint of bar2
         if(c0 > (o2 + c2) / 2.0) { sig.strength = 4; sig.patternName = "MorningStar+"; }
      }
   }

   //--- Evening Star (bearish): bar2=big bullish, bar1=small body, bar0=big bearish
   if(c2 > o2 && c0 < o0)
   {
      if(body2 > atr * minBodyATR && body0 > atr * minBodyATR && body1 < body2 * 0.4)
      {
         sig.direction = -1;
         sig.strength  = 3;
         sig.patternName = "EveningStar";
         if(c0 < (o2 + c2) / 2.0) { sig.strength = 4; sig.patternName = "EveningStar+"; }
      }
   }

   return sig;
}

//+------------------------------------------------------------------+
//| OB Flip (Order Block)                                            |
//| Last opposing candle before a strong move = institutional zone   |
//+------------------------------------------------------------------+
PASignal PA_DetectOBFlip(MqlRates &rates[], int count, double atr,
                          double minMoveATR = 1.0)
{
   PASignal sig = {0, 0, ""};
   if(count < 4 || atr <= 0) return sig;

   //--- Bullish OB flip: bar[3]=bearish (last bear bar before big up move)
   //--- bar[2] and bar[1] should show strong bullish movement
   double move_up   = rates[1].close - rates[3].low;
   double move_down = rates[3].high - rates[1].close;

   //--- Bullish OB: prev bearish bar + strong bullish follow-through
   if(rates[3].close < rates[3].open) // bar3 bearish
   {
      if(move_up > atr * minMoveATR)
      {
         sig.direction = +1;
         sig.strength  = 3;
         sig.patternName = "OB_BullFlip";
         //--- Boost: bar[0] (forming) pulls back to bar[3] body
         double obHigh = MathMax(rates[3].open, rates[3].close);
         double obLow  = MathMin(rates[3].open, rates[3].close);
         if(rates[0].low <= obHigh && rates[0].low >= obLow)
         { sig.strength = 4; sig.patternName = "OB_BullFlip+Retest"; }
      }
   }

   //--- Bearish OB flip
   if(rates[3].close > rates[3].open) // bar3 bullish
   {
      if(move_down > atr * minMoveATR)
      {
         sig.direction = -1;
         sig.strength  = 3;
         sig.patternName = "OB_BearFlip";
         double obHigh = MathMax(rates[3].open, rates[3].close);
         double obLow  = MathMin(rates[3].open, rates[3].close);
         if(rates[0].high >= obLow && rates[0].high <= obHigh)
         { sig.strength = 4; sig.patternName = "OB_BearFlip+Retest"; }
      }
   }

   return sig;
}

//+------------------------------------------------------------------+
//| BOS / CHoCH Detection                                            |
//| Break of Structure: price breaks a recent swing in trend dir.    |
//| Change of Character: price breaks a recent swing AGAINST trend.  |
//+------------------------------------------------------------------+
PASignal PA_DetectBOS(MqlRates &rates[], int count, double swingHigh, double swingLow, double atr)
{
   PASignal sig = {0, 0, ""};
   if(count < 2 || atr <= 0) return sig;

   double close = rates[1].close; // last closed bar

   //--- Bullish BOS: close breaks above recent swing high
   if(swingHigh > 0 && close > swingHigh + atr * 0.1)
   {
      sig.direction = +1;
      sig.strength  = 3;
      sig.patternName = "BOS_Bull";
   }

   //--- Bearish BOS: close breaks below recent swing low
   if(swingLow > 0 && close < swingLow - atr * 0.1)
   {
      sig.direction = -1;
      sig.strength  = 3;
      sig.patternName = "BOS_Bear";
   }

   return sig;
}

//+------------------------------------------------------------------+
//| Aggregate Price Action Score                                     |
//| Scans multiple patterns and returns the strongest direction      |
//| with cumulative score.                                           |
//+------------------------------------------------------------------+
PASignal PA_AggregateScore(MqlRates &rates[], int count, double atr,
                            double swingHigh, double swingLow,
                            double minWickATR = 0.5, double wickBodyRatio = 2.0,
                            double minBodyATR = 0.15, double minMoveATR = 1.0)
{
   PASignal best = {0, 0, ""};

   //--- Pin bar (on bar[1] using bar[2] as context)
   if(count >= 2)
   {
      PASignal pin = PA_DetectPinBar(rates[1], rates[2], atr, minWickATR, wickBodyRatio);
      if(pin.direction != 0 && pin.strength > best.strength)
         best = pin;
   }

   //--- Engulfing (bar[0] vs bar[1])  — but bar[0] may be forming, so use bar[1] vs bar[2]
   if(count >= 3)
   {
      PASignal eng = PA_DetectEngulfing(rates[1], rates[2], atr, minBodyATR);
      if(eng.direction != 0 && eng.strength > best.strength)
         best = eng;
   }

   //--- Pin+Engulf combo
   if(count >= 4)
   {
      PASignal combo = PA_DetectPinEngulfCombo(rates, count, atr, minWickATR, wickBodyRatio, minBodyATR);
      if(combo.direction != 0 && combo.strength > best.strength)
         best = combo;
   }

   //--- Three-bar reversal
   if(count >= 4)
   {
      PASignal tbr = PA_DetectThreeBarReversal(rates, count, atr, minBodyATR);
      if(tbr.direction != 0 && tbr.strength > best.strength)
         best = tbr;
   }

   //--- OB flip
   if(count >= 4)
   {
      PASignal ob = PA_DetectOBFlip(rates, count, atr, minMoveATR);
      if(ob.direction != 0 && ob.strength > best.strength)
         best = ob;
   }

   //--- BOS
   if(count >= 2)
   {
      PASignal bos = PA_DetectBOS(rates, count, swingHigh, swingLow, atr);
      if(bos.direction != 0 && bos.strength > best.strength)
         best = bos;
   }

   //--- Inside bar (lower priority)
   if(count >= 3)
   {
      PASignal ib = PA_DetectInsideBar(rates[1], rates[2], atr);
      if(ib.direction != 0 && best.direction == 0)
         best = ib;
   }

   return best;
}

#endif // PRICE_ACTION_PATTERNS_MQH

//--- END INLINE: PriceActionPatterns.mqh ---
//--- INLINE: SupportResistance.mqh ---
//+------------------------------------------------------------------+
//|                                        SupportResistance.mqh     |
//|                      Multi-TF Support & Resistance Detection     |
//|                      Swing-based with zone clustering             |
//|                                                                  |
//|  Features:                                                       |
//|  - Swing high/low detection across multiple timeframes           |
//|  - Zone clustering (merge nearby swing levels)                   |
//|  - Touch counting (more touches = stronger level)                |
//|  - Freshness scoring (untested levels are strongest)             |
//|  - HTF (H4/D1) structural S/R as major levels                   |
//|  - MTF confluence: level present on 2+ TFs = stronger           |
//+------------------------------------------------------------------+
#ifndef SUPPORT_RESISTANCE_MQH
#define SUPPORT_RESISTANCE_MQH

#define SR_MAX_LEVELS 20
#define SR_MAX_TOUCHES 10

//+------------------------------------------------------------------+
//| S/R level                                                        |
//+------------------------------------------------------------------+
enum SRLevelType
{
   SR_SUPPORT,      // Support level
   SR_RESISTANCE    // Resistance level
};

struct SRLevel
{
   SRLevelType  type;
   double       price;          // level center price
   double       upper;          // zone upper boundary
   double       lower;          // zone lower boundary
   int          touches;        // number of times price tested this level
   int          timeframes;     // bitmask: which TFs this level exists on (1=M1,2=M5,4=M15,8=M30,16=H1,32=H4,64=D1)
   double       strength;       // 0..1 composite score (touches + MTF confluence + freshness)
   datetime     firstSeen;      // when level was first detected
   datetime     lastTest;       // when price last touched this level
   bool         tested;         // has price bounced from this level at least once
};

//+------------------------------------------------------------------+
//| S/R scan result                                                  |
//+------------------------------------------------------------------+
struct SRResult
{
   SRLevel     supports[];     // support levels (sorted nearest-first)
   SRLevel     resistances[];  // resistance levels (sorted nearest-first)
   int         supportCount;
   int         resistanceCount;
   bool        valid;
};

//+------------------------------------------------------------------+
//| S/R scan state (persistent per EA instance)                     |
//+------------------------------------------------------------------+
struct SRState
{
   SRResult    current;
   datetime    lastScan;
};

//+------------------------------------------------------------------+
//| Get timeframe bitmask                                             |
//+------------------------------------------------------------------+
int SR_TFBitmask(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return 1;
      case PERIOD_M5:  return 2;
      case PERIOD_M15: return 4;
      case PERIOD_M30: return 8;
      case PERIOD_H1:  return 16;
      case PERIOD_H4:  return 32;
      case PERIOD_D1:  return 64;
      default:         return 0;
   }
}

//+------------------------------------------------------------------+
//| Detect swing points from a single timeframe                      |
//| Returns swing highs and lows as price arrays                    |
//+------------------------------------------------------------------+
void SR_DetectSwings(string symbol, ENUM_TIMEFRAMES tf, int lookback,
                     int swingLen, double &highs[], double &lows[])
{
   ArrayResize(highs, 0);
   ArrayResize(lows, 0);

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(symbol, tf, 0, lookback, rates) < lookback) return;

   for(int i = swingLen; i < lookback - swingLen; i++)
   {
      //--- Swing high
      bool isHigh = true;
      for(int j = 1; j <= swingLen; j++)
      {
         if(rates[i].high <= rates[i-j].high || rates[i].high <= rates[i+j].high)
         { isHigh = false; break; }
      }
      if(isHigh)
      {
         int sz = ArraySize(highs);
         ArrayResize(highs, sz + 1);
         highs[sz] = rates[i].high;
      }

      //--- Swing low
      bool isLow = true;
      for(int j = 1; j <= swingLen; j++)
      {
         if(rates[i].low >= rates[i-j].low || rates[i].low >= rates[i+j].low)
         { isLow = false; break; }
      }
      if(isLow)
      {
         int sz = ArraySize(lows);
         ArrayResize(lows, sz + 1);
         lows[sz] = rates[i].low;
      }
   }
}

//+------------------------------------------------------------------+
//| Merge nearby levels into zones (cluster within tolerance)        |
//+------------------------------------------------------------------+
void SR_MergeLevels(double &levels[], int count, double tolerance, double &merged[], int &mergedCount)
{
   if(count == 0) { mergedCount = 0; return; }

   //--- Sort ascending
   ArraySort(levels);

   ArrayResize(merged, count);
   mergedCount = 0;
   merged[0] = levels[0];
   double clusterSum = levels[0];
   int clusterCount = 1;

   for(int i = 1; i < count; i++)
   {
      if(levels[i] - merged[mergedCount] <= tolerance)
      {
         //--- Same cluster — average them
         clusterSum += levels[i];
         clusterCount++;
         merged[mergedCount] = clusterSum / clusterCount;
      }
      else
      {
         //--- New cluster
         mergedCount++;
         merged[mergedCount] = levels[i];
         clusterSum = levels[i];
         clusterCount = 1;
      }
   }
   mergedCount++;
}

//+------------------------------------------------------------------+
//| Count touches for a level (how many times price bounced)         |
//+------------------------------------------------------------------+
int SR_CountTouches(string symbol, ENUM_TIMEFRAMES tf, int lookback,
                    double level, double tolerance)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(symbol, tf, 0, lookback, rates) < 5) return 0;

   int touches = 0;
   for(int i = 0; i < lookback; i++)
   {
      //--- Price touched the level (wick into the zone)
      if(MathAbs(rates[i].high - level) <= tolerance ||
         MathAbs(rates[i].low - level) <= tolerance)
      {
         touches++;
      }
      //--- Also count if price opened or closed near the level
      if(MathAbs(rates[i].open - level) <= tolerance * 0.5 ||
         MathAbs(rates[i].close - level) <= tolerance * 0.5)
      {
         touches++;
      }
   }
   return touches;
}

//+------------------------------------------------------------------+
//| Check if level is on multiple timeframes                         |
//+------------------------------------------------------------------+
int SR_MultiTFScore(string symbol, double level, double tolerance)
{
   ENUM_TIMEFRAMES tfs[] = {PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H4, PERIOD_D1};
   int tfBits[] = {4, 8, 16, 32, 64};
   int score = 0;

   for(int t = 0; t < 5; t++)
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int cnt = CopyRates(symbol, tfs[t], 0, 200, rates);
      if(cnt < 20) continue;

      for(int i = 2; i < cnt - 2; i++)
      {
         //--- Swing high at level?
         bool isHigh = true;
         for(int j = 1; j <= 2; j++)
         {
            if(rates[i].high <= rates[i-j].high || rates[i].high <= rates[i+j].high)
            { isHigh = false; break; }
         }
         if(isHigh && MathAbs(rates[i].high - level) <= tolerance)
         { score |= tfBits[t]; break; }

         //--- Swing low at level?
         bool isLow = true;
         for(int j = 1; j <= 2; j++)
         {
            if(rates[i].low >= rates[i-j].low || rates[i].low >= rates[i+j].low)
            { isLow = false; break; }
         }
         if(isLow && MathAbs(rates[i].low - level) <= tolerance)
         { score |= tfBits[t]; break; }
      }
   }
   return score;
}

//+------------------------------------------------------------------+
//| Main S/R scan: detect levels from multiple TFs                  |
//|                                                                  |
//| entryTF   = entry timeframe (M5 or M15)                         |
//| structTF  = structure timeframe (M15 or H1)                     |
//| majorTFs  = higher TFs for major levels (H4, D1)               |
//| zoneATR   = zone thickness in ATR multiples                     |
//+------------------------------------------------------------------+
bool SR_Scan(SRState &state, string symbol,
             ENUM_TIMEFRAMES entryTF, ENUM_TIMEFRAMES structTF,
             double atr, double zoneATR = 0.5, int swingLen = 2)
{
   double tolerance = atr * zoneATR;
   if(tolerance <= 0) tolerance = atr * 0.5;

   //--- Collect swing levels from entry TF + structure TF + H4 + D1
   double allHighs[];
   double allLows[];
   int highCount = 0;
   int lowCount = 0;
   ArrayResize(allHighs, 0);
   ArrayResize(allLows, 0);

   ENUM_TIMEFRAMES scanTFs[] = {entryTF, structTF, PERIOD_H4, PERIOD_D1};
   int scanLookbacks[] = {100, 200, 300, 500};
   int scanSwingLens[] = {swingLen, swingLen, 3, 3}; // wider swings on HTF

   for(int t = 0; t < 4; t++)
   {
      double h[];
      double l[];
      SR_DetectSwings(symbol, scanTFs[t], scanLookbacks[t], scanSwingLens[t], h, l);

      //--- Append to master list
      for(int i = 0; i < ArraySize(h); i++)
      {
         int sz = ArraySize(allHighs);
         ArrayResize(allHighs, sz + 1);
         allHighs[sz] = h[i];
      }
      for(int i = 0; i < ArraySize(l); i++)
      {
         int sz = ArraySize(allLows);
         ArrayResize(allLows, sz + 1);
         allLows[sz] = l[i];
      }
   }

   //--- Merge nearby swing highs → resistance levels
   double mergedH[];
   int mergedHCount = 0;
   SR_MergeLevels(allHighs, ArraySize(allHighs), tolerance, mergedH, mergedHCount);

   //--- Merge nearby swing lows → support levels
   double mergedL[];
   int mergedLCount = 0;
   SR_MergeLevels(allLows, ArraySize(allLows), tolerance, mergedL, mergedLCount);

   //--- Build resistance levels
   ArrayResize(state.current.resistances, SR_MAX_LEVELS);
   state.current.resistanceCount = 0;

   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   for(int i = 0; i < mergedHCount && state.current.resistanceCount < SR_MAX_LEVELS; i++)
   {
      double level = mergedH[i];
      //--- Only keep levels above current price (resistance)
      if(level <= bid + atr * 0.2) continue;

      SRLevel sl;
      sl.type = SR_RESISTANCE;
      sl.price = level;
      sl.upper = level + tolerance * 0.5;
      sl.lower = level - tolerance * 0.5;
      sl.touches = SR_CountTouches(symbol, entryTF, 200, level, tolerance);
      sl.timeframes = SR_MultiTFScore(symbol, level, tolerance);
      //--- MTF score: count number of TF bits set
      int mtfCount = 0;
      { int tfmask = sl.timeframes; while(tfmask > 0) { mtfCount += (tfmask & 1); tfmask >>= 1; } }
      sl.strength = MathMin(1.0, (double)sl.touches / 8.0 * 0.5 +
                                   (double)mtfCount / 5.0 * 0.5);
      sl.firstSeen = 0;
      sl.lastTest = 0;
      sl.tested = (sl.touches >= 2);

      state.current.resistances[state.current.resistanceCount] = sl;
      state.current.resistanceCount++;
   }

   //--- Build support levels
   ArrayResize(state.current.supports, SR_MAX_LEVELS);
   state.current.supportCount = 0;

   for(int i = 0; i < mergedLCount && state.current.supportCount < SR_MAX_LEVELS; i++)
   {
      double level = mergedL[i];
      if(level >= bid - atr * 0.2) continue;

      SRLevel sl;
      sl.type = SR_SUPPORT;
      sl.price = level;
      sl.upper = level + tolerance * 0.5;
      sl.lower = level - tolerance * 0.5;
      sl.touches = SR_CountTouches(symbol, entryTF, 200, level, tolerance);
      sl.timeframes = SR_MultiTFScore(symbol, level, tolerance);
      int mtfCount = 0;
      { int tfmask = sl.timeframes; while(tfmask > 0) { mtfCount += (tfmask & 1); tfmask >>= 1; } }
      sl.strength = MathMin(1.0, (double)sl.touches / 8.0 * 0.5 +
                                   (double)mtfCount / 5.0 * 0.5);
      sl.firstSeen = 0;
      sl.lastTest = 0;
      sl.tested = (sl.touches >= 2);

      state.current.supports[state.current.supportCount] = sl;
      state.current.supportCount++;
   }

   state.current.valid = (state.current.supportCount > 0 || state.current.resistanceCount > 0);
   state.lastScan = TimeCurrent();

   return state.current.valid;
}

//+------------------------------------------------------------------+
//| Is price near a support level?                                   |
//| Returns the support index or -1                                  |
//+------------------------------------------------------------------+
int SR_NearSupport(SRResult &result, double price, double tolerance)
{
   double minDist = DBL_MAX;
   int nearest = -1;
   for(int i = 0; i < result.supportCount; i++)
   {
      double dist = MathAbs(price - result.supports[i].price);
      if(dist <= tolerance && dist < minDist)
      { minDist = dist; nearest = i; }
   }
   return nearest;
}

//+------------------------------------------------------------------+
//| Is price near a resistance level?                                |
//| Returns the resistance index or -1                               |
//+------------------------------------------------------------------+
int SR_NearResistance(SRResult &result, double price, double tolerance)
{
   double minDist = DBL_MAX;
   int nearest = -1;
   for(int i = 0; i < result.resistanceCount; i++)
   {
      double dist = MathAbs(price - result.resistances[i].price);
      if(dist <= tolerance && dist < minDist)
      { minDist = dist; nearest = i; }
   }
   return nearest;
}

//+------------------------------------------------------------------+
//| Get nearest support below price (for SL placement)              |
//+------------------------------------------------------------------+
double SR_NearestSupportBelow(SRResult &result, double price)
{
   double best = 0;
   double minDist = DBL_MAX;
   for(int i = 0; i < result.supportCount; i++)
   {
      if(result.supports[i].price < price)
      {
         double dist = price - result.supports[i].price;
         if(dist < minDist) { minDist = dist; best = result.supports[i].price; }
      }
   }
   return best;
}

//+------------------------------------------------------------------+
//| Get nearest resistance above price (for TP target)              |
//+------------------------------------------------------------------+
double SR_NearestResistanceAbove(SRResult &result, double price)
{
   double best = 0;
   double minDist = DBL_MAX;
   for(int i = 0; i < result.resistanceCount; i++)
   {
      if(result.resistances[i].price > price)
      {
         double dist = result.resistances[i].price - price;
         if(dist < minDist) { minDist = dist; best = result.resistances[i].price; }
      }
   }
   return best;
}

//+------------------------------------------------------------------+
//| Get nearest support above price (for sell SL placement)         |
//+------------------------------------------------------------------+
double SR_NearestSupportAbove(SRResult &result, double price)
{
   double best = 0;
   double minDist = DBL_MAX;
   for(int i = 0; i < result.supportCount; i++)
   {
      if(result.supports[i].price > price)
      {
         double dist = result.supports[i].price - price;
         if(dist < minDist) { minDist = dist; best = result.supports[i].price; }
      }
   }
   return best;
}

//+------------------------------------------------------------------+
//| Get nearest resistance below price (for sell TP target)         |
//+------------------------------------------------------------------+
double SR_NearestResistanceBelow(SRResult &result, double price)
{
   double best = 0;
   double minDist = DBL_MAX;
   for(int i = 0; i < result.resistanceCount; i++)
   {
      if(result.resistances[i].price < price)
      {
         double dist = price - result.resistances[i].price;
         if(dist < minDist) { minDist = dist; best = result.resistances[i].price; }
      }
   }
   return best;
}

//+------------------------------------------------------------------+
//| Is price at support (buy zone)?                                  |
//+------------------------------------------------------------------+
bool SR_AtSupport(SRResult &result, double price, double tolerance)
{
   return SR_NearSupport(result, price, tolerance) >= 0;
}

//+------------------------------------------------------------------+
//| Is price at resistance (sell zone)?                              |
//+------------------------------------------------------------------+
bool SR_AtResistance(SRResult &result, double price, double tolerance)
{
   return SR_NearResistance(result, price, tolerance) >= 0;
}

//+------------------------------------------------------------------+
//| Print S/R summary for debugging                                  |
//+------------------------------------------------------------------+
void SR_PrintLevels(SRResult &result, string symbol)
{
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   Print(symbol, " S/R | Supports=", result.supportCount,
         " Resistances=", result.resistanceCount);
   for(int i = 0; i < result.supportCount; i++)
   {
      Print("  S#", i, " price=", DoubleToString(result.supports[i].price, digits),
            " touches=", result.supports[i].touches,
            " tfBit=", result.supports[i].timeframes,
            " str=", DoubleToString(result.supports[i].strength, 2));
   }
   for(int i = 0; i < result.resistanceCount; i++)
   {
      Print("  R#", i, " price=", DoubleToString(result.resistances[i].price, digits),
            " touches=", result.resistances[i].touches,
            " tfBit=", result.resistances[i].timeframes,
            " str=", DoubleToString(result.resistances[i].strength, 2));
   }
}

#endif // SUPPORT_RESISTANCE_MQH

//--- END INLINE: SupportResistance.mqh ---
//--- INLINE: WeeklyVolumeProfile.mqh ---
//+------------------------------------------------------------------+
//|                                       WeeklyVolumeProfile.mqh     |
//|             Weekly Volume Profile — CW POC/VAH/VAL computation   |
//|                                                                    |
//|  Scans the last 5 trading days of M15 bars and builds a volume   |
//|  histogram. Returns the Current Week POC, Value Area High and    |
//|  Value Area Low — the key levels used by Syndicate / Shadow Intel|
//|  style VP traders.                                                 |
//+------------------------------------------------------------------+
#ifndef WEEKLY_VOLUME_PROFILE_MQH
#define WEEKLY_VOLUME_PROFILE_MQH

//--- Weekly VP result
struct WeeklyVPResult
{
   double   poc;           // Point of Control (most volume)
   double   vah;           // Value Area High
   double   val;           // Value Area Low
   double   hvn;           // High Volume Node (2nd highest peak)
   double   weekHigh;      // Week's absolute high
   double   weekLow;       // Week's absolute low
   int      totalBars;     // Bars scanned
   bool     valid;
};

//+------------------------------------------------------------------+
//| Compute weekly volume profile from M15 bars                      |
//| bucketSize = minimum price increment per bucket                  |
//| vaPct      = value area percentage (70 = 70% of volume)          |
//| brokerGMT  = broker's GMT offset for Monday detection            |
//+------------------------------------------------------------------+
bool WeeklyVP_Compute(WeeklyVPResult &result,
                      string symbol,
                      double bucketSize,
                      double vaPct,
                      int brokerGMT)
{
   result.valid = false;
   result.poc = 0; result.vah = 0; result.val = 0;
   result.hvn = 0; result.weekHigh = 0; result.weekLow = 0;
   result.totalBars = 0;

   if(bucketSize <= 0) bucketSize = 0.50; // default for gold

   //--- Find this week's Monday 00:00 GMT
   MqlDateTime now;
   TimeTradeServer(now);
   int dayOfWeek = now.day_of_week; // 0=Sun,1=Mon,...

   //--- Go back to Monday 00:00 GMT
   int daysSinceMonday = (dayOfWeek == 0) ? 6 : (dayOfWeek - 1);
   datetime weekStartGMT = TimeTradeServer() - (datetime)(daysSinceMonday * 86400);
   //--- Normalize to 00:00 GMT
   MqlDateTime wsDt;
   TimeToStruct(weekStartGMT, wsDt);
   wsDt.hour = 0; wsDt.min = 0; wsDt.sec = 0;
   weekStartGMT = StructToTime(wsDt);

   //--- Account for broker offset
   datetime weekStartBroker = weekStartGMT + (datetime)(brokerGMT * 3600);

   //--- Load M15 bars from this week
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(symbol, PERIOD_M15, weekStartBroker, 500, rates);
   if(copied < 10) return false;

   //--- Find price extent
   double lo = 1e9, hi = 0;
   int n = 0;
   for(int i = 0; i < copied; i++)
   {
      if(rates[i].time < weekStartBroker) continue;
      if(rates[i].low  < lo) lo = rates[i].low;
      if(rates[i].high > hi) hi = rates[i].high;
      n++;
   }
   if(n < 10 || hi <= lo) return false;

   result.weekHigh = hi;
   result.weekLow  = lo;
   result.totalBars = n;

   //--- Build histogram
   int nb = (int)MathCeil((hi - lo) / bucketSize) + 1;
   if(nb < 2 || nb > 2000) return false;

   double volA[];
   ArrayResize(volA, nb);
   ArrayInitialize(volA, 0.0);

   for(int i = 0; i < copied; i++)
   {
      if(rates[i].time < weekStartBroker) continue;

      double vol = (rates[i].tick_volume > 0) ? (double)rates[i].tick_volume : 1.0;
      int b0 = (int)MathFloor((rates[i].low  - lo) / bucketSize);
      int b1 = (int)MathFloor((rates[i].high - lo) / bucketSize);
      if(b0 < 0) b0 = 0;
      if(b1 >= nb) b1 = nb - 1;
      int span = b1 - b0 + 1;
      double per = vol / span;
      for(int b = b0; b <= b1; b++) volA[b] += per;
   }

   //--- Find POC (highest volume bucket)
   int pocIdx = 0;
   double totalVol = 0;
   for(int b = 0; b < nb; b++)
   {
      totalVol += volA[b];
      if(volA[b] > volA[pocIdx]) pocIdx = b;
   }
   if(totalVol <= 0) return false;

   //--- Find HVN (2nd highest peak — skip POC and its neighbors)
   int hvnIdx = -1;
   double hvnVol = 0;
   for(int b = 0; b < nb; b++)
   {
      if(MathAbs(b - pocIdx) <= 1) continue; // skip POC neighborhood
      if(volA[b] > hvnVol) { hvnVol = volA[b]; hvnIdx = b; }
   }

   //--- Value Area: expand from POC taking the fatter neighbour
   double vaTarget = totalVol * vaPct / 100.0;
   double vaVol = volA[pocIdx];
   int loIdx = pocIdx, hiIdx = pocIdx;
   while(vaVol < vaTarget && (loIdx > 0 || hiIdx < nb - 1))
   {
      double dn = (loIdx > 0)      ? volA[loIdx - 1] : -1;
      double up = (hiIdx < nb - 1) ? volA[hiIdx + 1] : -1;
      if(up >= dn) { hiIdx++; vaVol += volA[hiIdx]; }
      else         { loIdx--; vaVol += volA[loIdx]; }
   }

   result.poc = NormalizeDouble(lo + (pocIdx + 0.5) * bucketSize, _Digits);
   result.vah = NormalizeDouble(lo + (hiIdx + 1.0) * bucketSize, _Digits);
   result.val = NormalizeDouble(lo + loIdx * bucketSize, _Digits);
   if(hvnIdx >= 0)
      result.hvn = NormalizeDouble(lo + (hvnIdx + 0.5) * bucketSize, _Digits);
   result.valid = true;

   return true;
}

#endif

//--- END INLINE: WeeklyVolumeProfile.mqh ---
//--- INLINE: FXRE_SwingSD.mqh ---
//+------------------------------------------------------------------+
//|                                            FXRE_SwingSD.mqh       |
//|               FXRE Hybrid — Swing-point Supply & Demand Zones     |
//+------------------------------------------------------------------+
//| Detects swing highs (supply) and swing lows (demand) on M15,
//| clusters nearby swings into zones, assigns strength based on
//| follow-through distance.
//+------------------------------------------------------------------+

//--- Swing-point S&D structure
struct SwingSDZone
{
   datetime   formationTime;
   double     priceHigh;
   double     priceLow;
   double     priceMid;
   bool       isDemand;      // true=demand(buy), false=supply(sell)
   double     strength;      // 1.0 to 5.0 (higher = stronger)
   int        ageCandles;    // candles since last swing in cluster
   int        swingCount;    // number of swings clustered
   double     zoneWidth;     // priceHigh - priceLow
};

//--- Module state
SwingSDZone g_swingBullish[];   // Demand zones
SwingSDZone g_swingBearish[];   // Supply zones
int   g_swingBullishTotal = 0;
int   g_swingBearishTotal = 0;

//+------------------------------------------------------------------+
//| Detect swing points & build zones                                |
//| Returns total zone count                                         |
//+------------------------------------------------------------------+
int DetectSwingZones(ENUM_TIMEFRAMES tf, int lookbackBars, int swingLookback,
                     double clusterPoints, int maxAge, double minStrength)
{
   ArrayFree(g_swingBullish);
   ArrayFree(g_swingBearish);
   g_swingBullishTotal = 0;
   g_swingBearishTotal = 0;

   if(lookbackBars < 20) return 0;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, tf, 0, lookbackBars + swingLookback * 2 + 5, rates);
   if(copied < lookbackBars) return 0;

   int look = swingLookback;
   double clusterThresh = clusterPoints;

   //--- Collect raw swing points
   struct RawSwing { double price; int idx; int strength; bool isDemand; };
   RawSwing rawSwings[];
   int rawCount = 0;
   ArrayResize(rawSwings, 5000);

   for(int i = look; i < lookbackBars - look; i++)
   {
      //--- Swing high (supply potential)
      bool isHigh = true;
      for(int k = 1; k <= look; k++)
      {
         if(rates[i].high < rates[i - k].high ||
            rates[i].high < rates[i + k].high ||
            rates[i].high <= rates[i - 1].high)
         { isHigh = false; break; }
      }
      if(isHigh)
      {
         int str = 1;
         for(int k = 1; k <= look; k++)
            if(rates[i].close > rates[i + k].close) str++;
         rawSwings[rawCount].price   = rates[i].high;
         rawSwings[rawCount].idx     = i;
         rawSwings[rawCount].strength = MathMin(str, 5);
         rawSwings[rawCount].isDemand = false;
         rawCount++;
      }

      //--- Swing low (demand potential)
      bool isLow = true;
      for(int k = 1; k <= look; k++)
      {
         if(rates[i].low > rates[i - k].low ||
            rates[i].low > rates[i + k].low ||
            rates[i].low >= rates[i - 1].low)
         { isLow = false; break; }
      }
      if(isLow)
      {
         int str = 1;
         for(int k = 1; k <= look; k++)
            if(rates[i].close < rates[i + k].close) str++;
         rawSwings[rawCount].price   = rates[i].low;
         rawSwings[rawCount].idx     = i;
         rawSwings[rawCount].strength = MathMin(str, 5);
         rawSwings[rawCount].isDemand = true;
         rawCount++;
      }
   }

   if(rawCount == 0) return 0;

   //--- Sort raw swings by price
   bool swapped = true;
   while(swapped)
   {
      swapped = false;
      for(int i = 0; i < rawCount - 1; i++)
      {
         if(rawSwings[i].price > rawSwings[i + 1].price)
         {
            RawSwing t = rawSwings[i]; rawSwings[i] = rawSwings[i + 1]; rawSwings[i + 1] = t;
            swapped = true;
         }
      }
   }

   //--- Cluster nearby swings into zones (separate demand/supply)
   // Process demand swings
   SwingSDZone tempDZ[], tempSZ[];
   int dzCount = 0, szCount = 0;
   ArrayResize(tempDZ, rawCount);
   ArrayResize(tempSZ, rawCount);

   // Cluster demand
   int start = 0;
   for(int i = 0; i < rawCount; i++)
   {
      if(!rawSwings[i].isDemand) continue;
      if(dzCount == 0 || rawSwings[i].price - tempDZ[dzCount - 1].priceHigh > clusterThresh)
      {
         // New cluster
         tempDZ[dzCount].formationTime = rates[rawSwings[i].idx].time;
         tempDZ[dzCount].priceHigh = rawSwings[i].price;
         tempDZ[dzCount].priceLow  = rawSwings[i].price;
         tempDZ[dzCount].priceMid  = rawSwings[i].price;
         tempDZ[dzCount].isDemand  = true;
         tempDZ[dzCount].strength  = (double)rawSwings[i].strength;
         tempDZ[dzCount].ageCandles = rawSwings[i].idx;
         tempDZ[dzCount].swingCount = 1;
         tempDZ[dzCount].zoneWidth  = 0;
         dzCount++;
      }
      else
      {
         // Add to existing cluster
         int ci = dzCount - 1;
         if(rawSwings[i].price > tempDZ[ci].priceHigh) tempDZ[ci].priceHigh = rawSwings[i].price;
         if(rawSwings[i].price < tempDZ[ci].priceLow)  tempDZ[ci].priceLow  = rawSwings[i].price;
         tempDZ[ci].priceMid = (tempDZ[ci].priceHigh + tempDZ[ci].priceLow) / 2.0;
         tempDZ[ci].strength = (tempDZ[ci].strength * tempDZ[ci].swingCount + rawSwings[i].strength)
                              / (tempDZ[ci].swingCount + 1);
         tempDZ[ci].swingCount++;
         if(rawSwings[i].idx > tempDZ[ci].ageCandles)
            tempDZ[ci].ageCandles = rawSwings[i].idx;
         tempDZ[ci].zoneWidth = tempDZ[ci].priceHigh - tempDZ[ci].priceLow;
      }
   }

   // Cluster supply
   for(int i = 0; i < rawCount; i++)
   {
      if(rawSwings[i].isDemand) continue;
      if(szCount == 0 || rawSwings[i].price - tempSZ[szCount - 1].priceHigh > clusterThresh)
      {
         tempSZ[szCount].formationTime = rates[rawSwings[i].idx].time;
         tempSZ[szCount].priceHigh = rawSwings[i].price;
         tempSZ[szCount].priceLow  = rawSwings[i].price;
         tempSZ[szCount].priceMid  = rawSwings[i].price;
         tempSZ[szCount].isDemand  = false;
         tempSZ[szCount].strength  = (double)rawSwings[i].strength;
         tempSZ[szCount].ageCandles = rawSwings[i].idx;
         tempSZ[szCount].swingCount = 1;
         tempSZ[szCount].zoneWidth  = 0;
         szCount++;
      }
      else
      {
         int ci = szCount - 1;
         if(rawSwings[i].price > tempSZ[ci].priceHigh) tempSZ[ci].priceHigh = rawSwings[i].price;
         if(rawSwings[i].price < tempSZ[ci].priceLow)  tempSZ[ci].priceLow  = rawSwings[i].price;
         tempSZ[ci].priceMid = (tempSZ[ci].priceHigh + tempSZ[ci].priceLow) / 2.0;
         tempSZ[ci].strength = (tempSZ[ci].strength * tempSZ[ci].swingCount + rawSwings[i].strength)
                              / (tempSZ[ci].swingCount + 1);
         tempSZ[ci].swingCount++;
         if(rawSwings[i].idx > tempSZ[ci].ageCandles)
            tempSZ[ci].ageCandles = rawSwings[i].idx;
         tempSZ[ci].zoneWidth = tempSZ[ci].priceHigh - tempSZ[ci].priceLow;
      }
   }

   //--- Filter by age, strength — copy to global arrays
   for(int i = 0; i < dzCount; i++)
   {
      if(tempDZ[i].ageCandles <= maxAge &&
         tempDZ[i].strength >= minStrength)
      {
         ArrayResize(g_swingBullish, g_swingBullishTotal + 1, 20);
         g_swingBullish[g_swingBullishTotal] = tempDZ[i];
         g_swingBullishTotal++;
      }
   }
   for(int i = 0; i < szCount; i++)
   {
      if(tempSZ[i].ageCandles <= maxAge &&
         tempSZ[i].strength >= minStrength)
      {
         ArrayResize(g_swingBearish, g_swingBearishTotal + 1, 20);
         g_swingBearish[g_swingBearishTotal] = tempSZ[i];
         g_swingBearishTotal++;
      }
   }

   // Sort by strength descending
   SortSwingZones(g_swingBullish, g_swingBullishTotal, true);
   SortSwingZones(g_swingBearish, g_swingBearishTotal, true);

   return g_swingBullishTotal + g_swingBearishTotal;
}

//+------------------------------------------------------------------+
//| Find nearest demand zone below/at price                          |
//+------------------------------------------------------------------+
bool GetNearestDemandZone(double price, double proximityATR, double atrValue,
                          SwingSDZone &zone)
{
   double nearestDist = DBL_MAX;
   int nearestIdx = -1;
   double thresh = atrValue * proximityATR;

   for(int i = 0; i < g_swingBullishTotal; i++)
   {
      // Price should be AT or ABOVE demand zone
      if(price < g_swingBullish[i].priceLow - thresh) continue;

      double dist = price - g_swingBullish[i].priceMid;
      if(dist >= -thresh && dist < nearestDist)
      {
         nearestDist = dist;
         nearestIdx = i;
      }
   }

   if(nearestIdx >= 0)
   {
      zone = g_swingBullish[nearestIdx];
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Find nearest supply zone above/at price                          |
//+------------------------------------------------------------------+
bool GetNearestSupplyZone(double price, double proximityATR, double atrValue,
                          SwingSDZone &zone)
{
   double nearestDist = DBL_MAX;
   int nearestIdx = -1;
   double thresh = atrValue * proximityATR;

   for(int i = 0; i < g_swingBearishTotal; i++)
   {
      // Price should be AT or BELOW supply zone
      if(price > g_swingBearish[i].priceHigh + thresh) continue;

      double dist = g_swingBearish[i].priceMid - price;
      if(dist >= -thresh && dist < nearestDist)
      {
         nearestDist = dist;
         nearestIdx = i;
      }
   }

   if(nearestIdx >= 0)
   {
      zone = g_swingBearish[nearestIdx];
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Sort zones by strength descending (true) or ascending            |
//+------------------------------------------------------------------+
void SortSwingZones(SwingSDZone &zones[], int count, bool descending)
{
   for(int i = 0; i < count - 1; i++)
      for(int j = i + 1; j < count; j++)
         if(descending ? (zones[j].strength > zones[i].strength)
                       : (zones[j].strength < zones[i].strength))
         { SwingSDZone t = zones[i]; zones[i] = zones[j]; zones[j] = t; }
}

//+------------------------------------------------------------------+
//| Print active zones                                               |
//+------------------------------------------------------------------+
void PrintSwingZones()
{
   Print("=== Demand Zones (BUY): ", g_swingBullishTotal, " ===");
   for(int i = 0; i < MathMin(g_swingBullishTotal, 5); i++)
      PrintFormat("DZ[%d] Time=%s Zone=[%.2f-%.2f] Str=%.1f Age=%d Swings=%d Width=%.2f",
         i, TimeToString(g_swingBullish[i].formationTime),
         g_swingBullish[i].priceLow, g_swingBullish[i].priceHigh,
         g_swingBullish[i].strength, g_swingBullish[i].ageCandles,
         g_swingBullish[i].swingCount, g_swingBullish[i].zoneWidth);

   Print("=== Supply Zones (SELL): ", g_swingBearishTotal, " ===");
   for(int i = 0; i < MathMin(g_swingBearishTotal, 5); i++)
      PrintFormat("SZ[%d] Time=%s Zone=[%.2f-%.2f] Str=%.1f Age=%d Swings=%d Width=%.2f",
         i, TimeToString(g_swingBearish[i].formationTime),
         g_swingBearish[i].priceLow, g_swingBearish[i].priceHigh,
         g_swingBearish[i].strength, g_swingBearish[i].ageCandles,
         g_swingBearish[i].swingCount, g_swingBearish[i].zoneWidth);
}
//+------------------------------------------------------------------+

//--- END INLINE: FXRE_SwingSD.mqh ---
//--- INLINE: MarketRegime.mqh ---
//+------------------------------------------------------------------+
//|                                            MarketRegime.mqh       |
//|               Market Regime Filter — Avoid Ranging Markets         |
//|               Uses ADX + ATR Compression + Session Volume          |
//+------------------------------------------------------------------+
#property copyright "XAU MATE Trading"
#property version   "1.00"
#property description "Market regime detection: Trending vs Ranging"

//--- Market Regime Enum
enum ENUM_MARKET_REGIME
{
   REGIME_TRENDING_UP,     // Trending Up (ADX > threshold, +DI > -DI)
   REGIME_TRENDING_DOWN,   // Trending Down (ADX > threshold, -DI > +DI)
   REGIME_RANGING,         // Ranging (ADX < threshold)
   REGIME_VOLATILE,        // High Volatility (ATR spike)
   REGIME_QUIET            // Low Volatility (ATR compression)
};

//+------------------------------------------------------------------+
//| Market Regime Detector Class                                      |
//+------------------------------------------------------------------+
class CMarketRegime
{
private:
   int      m_adxPeriod;
   int      m_atrPeriod;
   double   m_adxTrendThreshold;    // Above this = trending (default 25)
   double   m_adxStrongThreshold;   // Above this = strong trend (default 40)
   double   m_atrCompressionRatio;  // ATR/MA_ATR below this = compression
   double   m_atrExpansionRatio;    // ATR/MA_ATR above this = expansion
   int      m_maPeriod;             // MA period for ATR smoothing
   
   ENUM_MARKET_REGIME m_currentRegime;
   double   m_currentADX;
   double   m_currentPlusDI;
   double   m_currentMinusDI;
   double   m_currentATR;
   double   m_atrMA;
   double   m_atrRatio;
   bool     m_isRanging;
   bool     m_isTrending;
   bool     m_isVolatile;
   bool     m_isQuiet;
   
public:
   //--- Constructor
   CMarketRegime(int adxPeriod = 14, int atrPeriod = 14, int maPeriod = 50)
   {
      m_adxPeriod = adxPeriod;
      m_atrPeriod = atrPeriod;
      m_maPeriod = maPeriod;
      m_adxTrendThreshold = 25.0;
      m_adxStrongThreshold = 40.0;
      m_atrCompressionRatio = 0.7;
      m_atrExpansionRatio = 1.3;
      m_currentRegime = REGIME_RANGING;
      m_currentADX = 0;
      m_currentPlusDI = 0;
      m_currentMinusDI = 0;
      m_currentATR = 0;
      m_atrMA = 0;
      m_atrRatio = 1.0;
      m_isRanging = true;
      m_isTrending = false;
      m_isVolatile = false;
      m_isQuiet = false;
   }
   
   //--- Set thresholds
   void SetThresholds(double adxTrend = 25.0, double adxStrong = 40.0, 
                      double atrComp = 0.7, double atrExp = 1.3)
   {
      m_adxTrendThreshold = adxTrend;
      m_adxStrongThreshold = adxStrong;
      m_atrCompressionRatio = atrComp;
      m_atrExpansionRatio = atrExp;
   }
   
   //--- Calculate ADX and DI values
   bool CalcADX(ENUM_TIMEFRAMES tf = PERIOD_CURRENT)
   {
      double plusDI[], minusDI[], adx[];
      ArraySetAsSeries(plusDI, true);
      ArraySetAsSeries(minusDI, true);
      ArraySetAsSeries(adx, true);
      
      if(CopyBuffer(iADX(_Symbol, tf, m_adxPeriod, PRICE_CLOSE), 0, 0, m_adxPeriod + 5, adx) < m_adxPeriod)
         return false;
      if(CopyBuffer(iADX(_Symbol, tf, m_adxPeriod, PRICE_CLOSE), 1, 0, m_adxPeriod + 5, plusDI) < m_adxPeriod)
         return false;
      if(CopyBuffer(iADX(_Symbol, tf, m_adxPeriod, PRICE_CLOSE), 2, 0, m_adxPeriod + 5, minusDI) < m_adxPeriod)
         return false;
      
      m_currentADX = adx[0];
      m_currentPlusDI = plusDI[0];
      m_currentMinusDI = minusDI[0];
      
      return true;
   }
   
   //--- Calculate ATR and its moving average
   bool CalcATRRegime(ENUM_TIMEFRAMES tf = PERIOD_CURRENT)
   {
      double atr[];
      ArraySetAsSeries(atr, true);
      
      int atrHandle = iATR(_Symbol, tf, m_atrPeriod);
      if(atrHandle == INVALID_HANDLE) return false;
      
      if(CopyBuffer(atrHandle, 0, 0, m_maPeriod + 5, atr) < m_maPeriod)
         return false;
      
      m_currentATR = atr[0];
      
      // Calculate MA of ATR
      double sum = 0;
      for(int i = 0; i < m_maPeriod; i++)
         sum += atr[i];
      m_atrMA = sum / m_maPeriod;
      
      // ATR ratio (current / MA)
      m_atrRatio = (m_atrMA > 0) ? m_currentATR / m_atrMA : 1.0;
      
      return true;
   }
   
   //--- Detect market regime
   ENUM_MARKET_REGIME DetectRegime(ENUM_TIMEFRAMES tf = PERIOD_CURRENT)
   {
      if(!CalcADX(tf)) return REGIME_RANGING;
      if(!CalcATRRegime(tf)) return REGIME_RANGING;
      
      // Determine regime
      bool adxTrending = (m_currentADX >= m_adxTrendThreshold);
      bool adxStrong = (m_currentADX >= m_adxStrongThreshold);
      bool plusDIDominant = (m_currentPlusDI > m_currentMinusDI);
      bool minusDIDominant = (m_currentMinusDI > m_currentPlusDI);
      bool atrCompressed = (m_atrRatio < m_atrCompressionRatio);
      bool atrExpanded = (m_atrRatio > m_atrExpansionRatio);
      
      // Set boolean flags
      m_isRanging = !adxTrending || atrCompressed;
      m_isTrending = adxTrending && !atrCompressed;
      m_isVolatile = atrExpanded && adxTrending;
      m_isQuiet = atrCompressed && !adxTrending;
      
      // Determine regime
      if(adxStrong && plusDIDominant)
         m_currentRegime = REGIME_TRENDING_UP;
      else if(adxStrong && minusDIDominant)
         m_currentRegime = REGIME_TRENDING_DOWN;
      else if(adxTrending && plusDIDominant)
         m_currentRegime = REGIME_TRENDING_UP;
      else if(adxTrending && minusDIDominant)
         m_currentRegIME = REGIME_TRENDING_DOWN;
      else if(atrExpanded)
         m_currentRegime = REGIME_VOLATILE;
      else if(atrCompressed)
         m_currentRegime = REGIME_QUIET;
      else
         m_currentRegime = REGIME_RANGING;
      
      return m_currentRegime;
   }
   
   //--- Check if market is tradeable (not ranging)
   bool IsTradeable()
   {
      // Don't trade if:
      // 1. Market is ranging (ADX < 25)
      // 2. ATR is compressed (low volatility)
      // 3. ADX is falling (weakening trend)
      
      if(m_isRanging)
         return false;
      
      if(m_isQuiet)
         return false;
      
      // Check if ADX is rising (trend strengthening)
      // We use a simple check: ADX > 20 and not falling sharply
      if(m_currentADX < 20)
         return false;
      
      return true;
   }
   
   //--- Check if market is trending UP
   bool IsTrendingUp()
   {
      return (m_currentRegime == REGIME_TRENDING_UP && m_currentPlusDI > m_currentMinusDI);
   }
   
   //--- Check if market is trending DOWN
   bool IsTrendingDown()
   {
      return (m_currentRegime == REGIME_TRENDING_DOWN && m_currentMinusDI > m_currentPlusDI);
   }
   
   //--- Get regime name as string
   string GetRegimeName()
   {
      switch(m_currentRegime)
      {
         case REGIME_TRENDING_UP:    return "TRENDING UP";
         case REGIME_TRENDING_DOWN:  return "TRENDING DOWN";
         case REGIME_RANGING:        return "RANGING";
         case REGIME_VOLATILE:       return "VOLATILE";
         case REGIME_QUIET:          return "QUIET";
         default:                    return "UNKNOWN";
      }
   }
   
   //--- Get detailed status
   string GetStatusString()
   {
      string status = "Regime: " + GetRegimeName() + "\n";
      status += "ADX: " + DoubleToString(m_currentADX, 1) + " (+" + DoubleToString(m_currentPlusDI, 1) + "/-" + DoubleToString(m_currentMinusDI, 1) + ")\n";
      status += "ATR: " + DoubleToString(m_currentATR, 2) + " (MA: " + DoubleToString(m_atrMA, 2) + ")\n";
      status += "ATR Ratio: " + DoubleToString(m_atrRatio, 2) + "\n";
      status += "Tradeable: " + (IsTradeable() ? "YES" : "NO") + "\n";
      
      if(m_isRanging) status += "⚠️ Market is RANGING — avoid trading\n";
      if(m_isQuiet) status += "⚠️ Market is QUIET — low volatility\n";
      if(m_isVolatile) status += "⚡ Market is VOLATILE — use smaller lots\n";
      
      return status;
   }
   
   //--- Getters
   double GetADX() { return m_currentADX; }
   double GetPlusDI() { return m_currentPlusDI; }
   double GetMinusDI() { return m_currentMinusDI; }
   double GetATR() { return m_currentATR; }
   double GetATRMA() { return m_atrMA; }
   double GetATRRatio() { return m_atrRatio; }
   bool IsRanging() { return m_isRanging; }
   bool IsTrending() { return m_isTrending; }
   bool IsVolatile() { return m_isVolatile; }
   bool IsQuiet() { return m_isQuiet; }
};

//+------------------------------------------------------------------+
//| Global instance for quick access                                  |
//+------------------------------------------------------------------+
CMarketRegime g_marketRegime;

//+------------------------------------------------------------------+
//| Quick check function — returns true if market is tradeable        |
//+------------------------------------------------------------------+
bool IsMarketTradeable(ENUM_TIMEFRAMES tf = PERIOD_CURRENT)
{
   g_marketRegime.DetectRegime(tf);
   return g_marketRegime.IsTradeable();
}

//+------------------------------------------------------------------+
//| Get market direction bias (+1 = up, -1 = down, 0 = neutral)      |
//+------------------------------------------------------------------+
int GetMarketBias(ENUM_TIMEFRAMES tf = PERIOD_CURRENT)
{
   g_marketRegime.DetectRegime(tf);
   if(g_marketRegime.IsTrendingUp()) return 1;
   if(g_marketRegime.IsTrendingDown()) return -1;
   return 0;
}
//+------------------------------------------------------------------+

//--- END INLINE: MarketRegime.mqh ---

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
//--- General
input string   Inp_Gen            = "======== GENERAL ========";
input double   RiskPerTradePct    = 0.5;
input double   MaxDailyRiskPct    = 2.0;
input double   MaxSessDDPct       = 1.5;
input int      MaxTradesPerSess   = 5;
input int      MaxPositions       = 1;
input int      BrokerGMTOffset    = 2;  // Vantage broker GMT+2
input bool     DebugMode          = false;

//--- Market Regime Filter (NEW — avoid ranging markets)
input string   Inp_Regime         = "=== MARKET REGIME =====";
input bool     UseMarketRegime    = true;   // Enable market regime filter
input double   RegimeADXThreshold = 25.0;   // ADX above this = trending
input double   RegimeADXStrong    = 40.0;   // ADX above this = strong trend
input double   RegimeATRCompRatio = 0.7;    // ATR/MA below this = compression
input double   RegimeATRExpRatio  = 1.3;    // ATR/MA above this = expansion

//--- Timeframes
input string   Inp_TF             = "======= TIMEFRAMES =======";
input ENUM_TIMEFRAMES EntryTF     = PERIOD_M15;
input ENUM_TIMEFRAMES ProfileTF   = PERIOD_M15;
input int      SwingLookback      = 50;             // Swing lookback (was 100 — saves memory)

//--- FRVP Settings
input string   Inp_FRVP           = "===== FRVP SETTINGS ======";
input int      FRVP_Anchors       = 24;             // FRVP lookback bars (was 48 — 6h enough, saves memory)
input double   FRVP_BucketPips    = 0.50;           // FRVP bucket size (price units)
input double   FRVP_ValueAreaPct  = 70.0;           // Value area % (default 70)
input double   FRVP_HVNThreshold  = 0.70;           // HVN = vol >= 70% of POC
input double   FRVP_LVNThreshold  = 0.20;           // LVN = vol <= 20% of POC
input double   FRVP_ZoneTolATR    = 0.30;           // Zone entry tolerance (xATR)
input int      FRVP_RefreshBars   = 6;              // Recompute every N bars

//--- Price Action Settings
input string   Inp_PA             = "===== PRICE ACTION ======";
input double   PA_MinWickATR      = 0.5;            // Pin bar min wick (xATR)
input double   PA_WickBodyRatio   = 2.0;            // Pin bar wick/body ratio
input double   PA_MinBodyATR      = 0.15;           // Engulfing min body (xATR)
input double   PA_MinMoveATR      = 1.0;            // OB flip min move (xATR)
input bool     PA_RequireTrend    = true;            // PA must agree with MA trend

//--- Trend Filter (MA50/200)
input string   Inp_Trend          = "===== TREND FILTER ======";
input bool     EnableTrendFilter  = true;
input int      Trend_MA_Fast      = 20;    // Fast MA (was 50 — saves memory)
input int      Trend_MA_Slow      = 50;    // Slow MA (was 200 — saves memory)

//--- Risk Management
input string   Inp_RM             = "===== RISK MGMT ======";
input bool     UseBreakEven       = true;
input double   BE_ATR_Mult        = 0.6;
input bool     UseTrailing        = true;
input double   TrailStart_ATR     = 0.8;
input double   TrailStep_ATR      = 0.3;
input int      MaxSlippagePts     = 30;
input double   Min_SL_ATR         = 1.0;
input double   MaxLotSize         = 0.05;   // Hard max lot size (safety cap)
input int      CooldownSeconds    = 300;    // Minimum seconds between trades (5 min)
input int      MagicNumber        = 241107;
input string   CommentPrefix      = "SCALPX_EA";

//--- Support & Resistance
input string   Inp_SR             = "===== S/R SETTINGS ======";
input bool     EnableSR           = true;           // Use S/R confluence
input double   SR_ZoneATR         = 0.5;            // S/R zone thickness (xATR)
input int      SR_SwingLen        = 2;              // Swing bars each side
input double   SR_ScoreSupport    = 2;              // Confluence score: at support
input double   SR_ScoreResistance = 2;              // Confluence score: at resistance
input double   SR_ScoreMTF        = 1;              // Extra score: multi-TF confirmation

//--- Asia VP Mode (Shadow Intel style)
input string   Inp_AsiaVP         = "==== ASIA VP MODE ======";
input bool     EnableAsiaVP       = true;           // Asia-VP London sweep reversal ON
input double   AsiaVP_MinRangeATR = 2.0;            // Min Asian range to trade (xATR)
input bool     AsiaVP_UseFlow     = true;           // Require tick-flow confirmation
input int      AsiaVP_FlowWinMin  = 20;             // Tick-flow lookback window (minutes)

//--- VP-Pro Mode (Syndicate / Shadow Intel fusion)
input string   Inp_VPPro          = "==== VP-PRO MODE ======";
input bool     EnableVPPro        = false;          // VP-Pro: Weekly VP + Hard S/D + Order Flow
input double   VPPro_BucketPips   = 0.50;           // Weekly VP bucket size
input double   VPPro_VAAPct       = 70.0;           // Weekly VP value area %
input int      VPPro_RefreshBars  = 12;             // Recompute weekly VP every N bars
input double   VPPro_ZoneTolATR   = 0.4;            // Zone entry tolerance (xATR)
input double   VPPro_MinSDStr     = 3.0;            // Min S/D zone strength (1-5)
input double   VPPro_SDProxATR    = 2.0;            // S/D zone proximity (xATR)
input bool     VPPro_RequireFlow  = true;           // Require order flow confirmation
input int      VPPro_FlowWinMin   = 20;             // Flow lookback (minutes)
input double   VPPro_FlowThresh   = 0.55;           // Min buy/sell ratio to confirm

//--- Session Times in GMT
input string   Inp_Time           = "====== SESSION GMT TIMES ====";
input int      Asian_StartH       = 0;
input int      Asian_StartM       = 30;
input int      Asian_EndH         = 3;
input int      Asian_EndM         = 30;
input int      London_StartH      = 7;
input int      London_StartM      = 0;
input int      London_EndH        = 10;
input int      London_EndM        = 0;
input int      NY_StartH          = 13;
input int      NY_StartM          = 30;
input int      NY_EndH            = 16;
input int      NY_EndM            = 30;

//+------------------------------------------------------------------+
//| GLOBALS                                                          |
//+------------------------------------------------------------------+
CTrade         m_trade;
CPositionInfo  m_position;
CAccountInfo   m_account;

//--- FRVP state
FRVPState      g_frvp;

//--- S/R state
SRState        g_sr;

//--- Indicators
int            hMAFast = INVALID_HANDLE;
int            hMASlow = INVALID_HANDLE;

//--- Session tracking
enum SessionType { SESS_NONE = -1, SESS_ASIAN = 0, SESS_LONDON = 1, SESS_NY = 2 };
SessionType    g_currentSession = SESS_NONE;

//--- Asian range
double         g_asianHigh = 0;
double         g_asianLow  = 0;
datetime       g_asianSessionStart = 0;
bool           g_asianRangeReady = false;

//--- Daily stats
struct DailyStats
{
   double      startingBalance;
   int         tradeCount;
   int         sessionTradeCount;
   SessionType lastSession;
   bool        tradingStopped;
   bool        sessionActive;
   datetime    lastResetTime;
   double      sessionStartEquity;
   bool        sessTradingStopped;
};
DailyStats     g_stats;

//--- Misc
double         g_atrValue = 0;
datetime       g_lastBarTime = 0;
datetime       g_lastEntryBarTime = 0;
int            g_tickCount = 0;
string         g_commentPrefix = "XAU";
int            g_frvpRefreshCounter = 0;
datetime       g_lastTradeTime = 0;   // Cooldown timer

//--- Broker GMT offset
int            g_brokerGMTOffset = 0;

//--- Fill mode
ENUM_ORDER_TYPE_FILLING g_fillMode = ORDER_FILLING_FOK;

//--- Asia VP mode state (Shadow Intel)
double         g_asiaPOC = 0;
double         g_asiaVAH = 0;
double         g_asiaVAL = 0;
bool           g_asiaProfileValid = false;

//--- Tick-flow ring buffer (1-minute bins, ~1h history)
#define FLOW_BINS 70
double         g_flowBuy[FLOW_BINS];
double         g_flowSell[FLOW_BINS];
datetime       g_flowMinute[FLOW_BINS];
int            g_flowHead = -1;
double         g_lastFlowBid = 0;

//--- Weekly VP state (VP-Pro mode)
WeeklyVPResult g_wvp;
int            g_wvpRefreshCounter = 0;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   if(StringFind(_Symbol, "XAU") < 0 && StringFind(_Symbol, "GOLD") < 0)
      Print("WARNING: ScalpXAU is designed for XAUUSD. Current symbol: ", _Symbol);

   m_trade.SetExpertMagicNumber(MagicNumber);
   m_trade.SetDeviationInPoints(MaxSlippagePts);
   m_trade.SetAsyncMode(false);

   //--- Fill mode
   g_fillMode = ORDER_FILLING_FOK;
   long filling = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if(filling & SYMBOL_FILLING_FOK)      g_fillMode = ORDER_FILLING_FOK;
   else if(filling & SYMBOL_FILLING_IOC) g_fillMode = ORDER_FILLING_IOC;
   else                                  g_fillMode = ORDER_FILLING_RETURN;
   m_trade.SetTypeFilling(g_fillMode);
   Print("Fill mode: ", EnumToString(g_fillMode));

   //--- Trend MA handles
   hMAFast = iMA(_Symbol, EntryTF, Trend_MA_Fast, 0, MODE_SMA, PRICE_CLOSE);
   hMASlow = iMA(_Symbol, EntryTF, Trend_MA_Slow, 0, MODE_SMA, PRICE_CLOSE);
   if(hMAFast == INVALID_HANDLE || hMASlow == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create trend MA handles");
      return INIT_FAILED;
   }

   //--- Initialize FRVP
   g_frvp.lastCompute = 0;
   g_frvp.current.valid = false;
   g_frvpRefreshCounter = FRVP_RefreshBars; // force first compute

   //--- Initialize S/R
   g_sr.lastScan = 0;
   g_sr.current.valid = false;

   //--- Initialize stats
   g_stats.startingBalance = m_account.Balance();
   g_stats.tradeCount = 0;
   g_stats.sessionTradeCount = 0;
   g_stats.lastSession = SESS_NONE;
   g_stats.tradingStopped = false;
   g_stats.sessionActive = false;
   g_stats.lastResetTime = 0;
   g_stats.sessionStartEquity = m_account.Equity();
   g_stats.sessTradingStopped = false;

   //--- Broker GMT offset
   g_brokerGMTOffset = BrokerGMTOffset;
   if(g_brokerGMTOffset == -99)
   {
      g_brokerGMTOffset = (int)MathRound((TimeTradeServer() - TimeGMT()) / 3600.0);
      if(g_brokerGMTOffset < -14) g_brokerGMTOffset = -14;
      if(g_brokerGMTOffset > 14)  g_brokerGMTOffset = 14;
      Print("Broker GMT offset: AUTO = +", g_brokerGMTOffset);
   }

   Print("ScalpXAU v3.0 initialized on ", _Symbol, " ", EnumToString(EntryTF));
   Print("FRVP: anchors=", FRVP_Anchors, " bucket=", FRVP_BucketPips,
         " VA%=", FRVP_ValueAreaPct, " refresh every ", FRVP_RefreshBars, " bars");
   Print("PA: pin_wick=", PA_MinWickATR, "xATR wick/body>=", PA_WickBodyRatio,
         " engulf_body>=", PA_MinBodyATR, "xATR trend_gate=", PA_RequireTrend ? "ON" : "OFF");
   Print("Magic: ", MagicNumber, " | Risk: ", RiskPerTradePct, "% per trade, max ", MaxDailyRiskPct, "% daily");
   Print("AsiaVP: ", EnableAsiaVP ? "ON" : "OFF",
         " min_range=", AsiaVP_MinRangeATR, "xATR flow_confirm=", AsiaVP_UseFlow ? "ON" : "OFF",
         " win=", AsiaVP_FlowWinMin, "min");
   Print("VPPro: ", EnableVPPro ? "ON" : "OFF",
         " bucket=", VPPro_BucketPips, " VA%=", VPPro_VAAPct,
         " minSDStr=", VPPro_MinSDStr, " flow_confirm=", VPPro_RequireFlow ? "ON" : "OFF");
   //--- Initial weekly VP compute
   if(EnableVPPro)
   {
      if(WeeklyVP_Compute(g_wvp, _Symbol, VPPro_BucketPips, VPPro_VAAPct, g_brokerGMTOffset))
         Print("WeeklyVP | POC=", DoubleToString(g_wvp.poc, 2),
               " VAH=", DoubleToString(g_wvp.vah, 2),
               " VAL=", DoubleToString(g_wvp.val, 2),
               " bars=", g_wvp.totalBars);
   }

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(hMAFast != INVALID_HANDLE) IndicatorRelease(hMAFast);
   if(hMASlow != INVALID_HANDLE) IndicatorRelease(hMASlow);
   Comment("");
   Print("ScalpXAU deinitialized (reason: ", reason, ")");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Memory safety check (prevent VirtualAlloc errors)
   MEMORYSTATUSEX memInfo;
   memInfo.dwLength = sizeof(MEMORYSTATUSEX);
   if(GlobalMemoryStatusEx(memInfo))
   {
      DWORD freePhysMB = memInfo.ullAvailPhys / (1024 * 1024);
      if(freePhysMB < 100) // Less than 100MB free
      {
         static int lastMemWarn = 0;
         if(TimeCurrent() - lastMemWarn >= 60)
         {
            lastMemWarn = TimeCurrent();
            Print("MEMORY WARNING: Only ", freePhysMB, "MB free! Trading paused.");
         }
         UpdateComment();
         return;
      }
   }
   
   ResetDaily();

   if(g_stats.tradingStopped)
   {
      CloseAllPositions("DD_LIMIT");
      UpdateComment();
      return;
   }

   g_atrValue = CalcATR(14, EntryTF);
   g_tickCount++;
   AccumulateTickFlow();

   if(IsNewBar())
   {
      UpdateSwingPoints();
      DetectSessionLevels();

      //--- Refresh FRVP periodically
      g_frvpRefreshCounter++;
      if(g_frvpRefreshCounter >= FRVP_RefreshBars)
      {
         g_frvpRefreshCounter = 0;
         if(RefreshFRVP())
            FRVP_PrintProfile(g_frvp.current, _Symbol);
      }

      //--- Refresh S/R every 12 bars (~3h on M15)
      if(EnableSR && g_frvpRefreshCounter % 2 == 0)
      {
         if(SR_Scan(g_sr, _Symbol, EntryTF, PERIOD_M15, g_atrValue, SR_ZoneATR, SR_SwingLen))
         {
            if(DebugMode) SR_PrintLevels(g_sr.current, _Symbol);
         }
      }

      //--- Refresh weekly VP + S/D zones for VP-Pro mode
      if(EnableVPPro)
      {
         g_wvpRefreshCounter++;
         if(g_wvpRefreshCounter >= VPPro_RefreshBars)
         {
            g_wvpRefreshCounter = 0;
            if(WeeklyVP_Compute(g_wvp, _Symbol, VPPro_BucketPips, VPPro_VAAPct, g_brokerGMTOffset))
            {
               if(DebugMode)
                  Print("WeeklyVP | POC=", DoubleToString(g_wvp.poc, 2),
                        " VAH=", DoubleToString(g_wvp.vah, 2),
                        " VAL=", DoubleToString(g_wvp.val, 2));
            }
            //--- Also refresh S/D zones for VP-Pro
            DetectSwingZones(EntryTF, 500, SR_SwingLen,
                             VPPro_SDProxATR * g_atrValue, 240, VPPro_MinSDStr);
         }
      }

      Print("NEWBAR | Sess=", GetSessionName(GetCurrentSession()),
            " GMT=", GetGMTHour(), ":", StringFormat("%02d", GetGMTMin()),
            " ATR=", DoubleToString(g_atrValue, 1),
            " FRVP=", g_frvp.current.valid ? "OK" : "N/A",
            " POC=", g_frvp.current.valid ? DoubleToString(g_frvp.current.poc, 2) : "---");
   }

   if(g_tickCount >= 100)
   {
      g_tickCount = 0;
      Print("HB | Bal=$", DoubleToString(m_account.Balance(), 2),
            " Eq=$", DoubleToString(m_account.Equity(), 2),
            " Pos=", CountOpenPositions(),
            " Trades=", g_stats.tradeCount,
            " Sess=", GetSessionName(g_currentSession));
   }

   ManagePositions();

   if(CountOpenPositions() >= MaxPositions) { UpdateComment(); return; }

   CheckEntry();

   UpdateComment();
}

//+------------------------------------------------------------------+
//| Refresh FRVP computation                                         |
//+------------------------------------------------------------------+
bool RefreshFRVP()
{
   double bucketPips = FRVP_BucketPips;
   if(bucketPips <= 0) bucketPips = 0.50; // default for gold

   bool ok = FRVP_Compute(g_frvp, _Symbol, ProfileTF, FRVP_Anchors,
                           bucketPips, FRVP_ValueAreaPct,
                           FRVP_HVNThreshold, FRVP_LVNThreshold);
   if(!ok && DebugMode) Print("FRVP compute failed");
   return ok;
}

//+------------------------------------------------------------------+
//| Check for entry signals                                          |
//+------------------------------------------------------------------+
void CheckEntry()
{
   datetime entryBar = iTime(_Symbol, EntryTF, 0);
   if(entryBar == g_lastEntryBarTime) return;
   g_lastEntryBarTime = entryBar;

   g_currentSession = GetCurrentSession();
   if(g_currentSession == SESS_NONE) return;

   //--- Reset session counter on change
   if(g_stats.lastSession != g_currentSession)
   {
      g_stats.sessionTradeCount = 0;
      g_stats.sessionStartEquity = m_account.Equity();
      g_stats.sessTradingStopped = false;
      g_stats.lastSession = g_currentSession;
      Print("SESS START | ", GetSessionName(g_currentSession),
            " Eq=$", DoubleToString(g_stats.sessionStartEquity, 2));
   }

   //--- Session DD limit
   if(!g_stats.sessTradingStopped && g_stats.sessionStartEquity > 0)
   {
      double ddPct = (g_stats.sessionStartEquity - m_account.Equity()) / g_stats.sessionStartEquity * 100.0;
      if(ddPct >= MaxSessDDPct)
      {
         g_stats.sessTradingStopped = true;
         Print("*** SESSION DD LIMIT: ", DoubleToString(ddPct, 2), "% ***");
      }
   }
   if(g_stats.sessTradingStopped) return;
   if(g_stats.sessionTradeCount >= MaxTradesPerSess) return;

   //--- Cooldown: minimum time between trades
   if(g_lastTradeTime > 0 && (TimeCurrent() - g_lastTradeTime) < CooldownSeconds)
   {
      static datetime lastCooldownWarn = 0;
      if(TimeCurrent() - lastCooldownWarn >= 60)
      {
         lastCooldownWarn = TimeCurrent();
         Print("COOLDOWN: Waiting ", CooldownSeconds - (int)(TimeCurrent() - g_lastTradeTime), "s");
      }
      return;
   }
   
   //--- MARKET REGIME FILTER: Skip if market is ranging
   if(UseMarketRegime)
   {
      g_marketRegime.SetThresholds(RegimeADXThreshold, RegimeADXStrong, RegimeATRCompRatio, RegimeATRExpRatio);
      g_marketRegime.DetectRegime(EntryTF);
      
      if(!g_marketRegime.IsTradeable())
      {
         static int lastRegimeWarn = 0;
         if(TimeCurrent() - lastRegimeWarn >= 300)
         {
            lastRegimeWarn = TimeCurrent();
            Print("REGIME BLOCK: ", g_marketRegime.GetRegimeName(),
                  " | ADX=", DoubleToString(g_marketRegime.GetADX(), 1),
                  " | ATR Ratio=", DoubleToString(g_marketRegime.GetATRRatio(), 2),
                  " | NOT TRADEABLE");
         }
         return;
      }
      
      if(DebugMode)
      {
         static int lastRegimeInfo = 0;
         if(TimeCurrent() - lastRegimeInfo >= 60)
         {
            lastRegimeInfo = TimeCurrent();
            Print("REGIME OK: ", g_marketRegime.GetRegimeName(),
                  " | ADX=", DoubleToString(g_marketRegime.GetADX(), 1),
                  " | +DI=", DoubleToString(g_marketRegime.GetPlusDI(), 1),
                  " | -DI=", DoubleToString(g_marketRegime.GetMinusDI(), 1),
                  " | ATR Ratio=", DoubleToString(g_marketRegime.GetATRRatio(), 2));
         }
      }
   }

   //--- Need FRVP valid for entries
   if(!g_frvp.current.valid)
   {
      if(DebugMode) Print("FRVP not ready — skipping entry");
      return;
   }

   //--- Get trend direction
   int trendDir = GetTrendDirection();

   //--- Session-specific logic
   switch(g_currentSession)
   {
      case SESS_ASIAN:
         CheckAsianEntry(trendDir);
         break;
      case SESS_LONDON:
         if(EnableVPPro && CheckVPProEntry(trendDir)) break;
         if(EnableAsiaVP && CheckLondonSweepEntry(trendDir)) break;
         CheckLondonEntry(trendDir);
         break;
      case SESS_NY:
         if(EnableVPPro && CheckVPProEntry(trendDir)) break;
         CheckNYEntry(trendDir);
         break;
   }
}

//+------------------------------------------------------------------+
//| Get trend direction from MA50/200                                |
//+------------------------------------------------------------------+
int GetTrendDirection()
{
   if(!EnableTrendFilter) return 0; // no filter = both directions OK

   double maF[], maSlow[];
   ArraySetAsSeries(maF, true);
   ArraySetAsSeries(maSlow, true);
   if(CopyBuffer(hMAFast, 0, 0, 3, maF) < 3) return 0;
   if(CopyBuffer(hMASlow, 0, 0, 3, maSlow) < 3) return 0;

   if(maF[0] > maSlow[0] && maF[1] > maSlow[1]) return +1;
   if(maF[0] < maSlow[0] && maF[1] < maSlow[1]) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| ASIAN SESSION: Range at FRVP zones                               |
//| Trade pin bars at VAL (buy) or VAH (sell) during ranging Asian   |
//+------------------------------------------------------------------+
void CheckAsianEntry(int trendDir)
{
   if(!g_asianRangeReady || g_asianHigh <= 0 || g_asianLow <= 0) return;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, EntryTF, 0, 5, rates) < 3) return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double atr = g_atrValue;
   if(atr <= 0) return;

   double zoneTol = atr * FRVP_ZoneTolATR;
   FRVPResult prof = g_frvp.current;

   //--- Get price action on last 2 closed bars
   PASignal pa = PA_AggregateScore(rates, 5, atr,
                                    prof.vah, prof.val,
                                    PA_MinWickATR, PA_WickBodyRatio,
                                    PA_MinBodyATR, PA_MinMoveATR);

   //--- BUY: price at VAL + bullish PA + not in downtrend + support nearby
   if(pa.direction == +1)
   {
      bool atVAL = FRVP_AtVAL(prof, bid, zoneTol);
      bool atLVN = FRVP_NearLVN(prof, bid, zoneTol) >= 0;
      bool trendOk = (!PA_RequireTrend || trendDir >= 0);
      bool atSupp = EnableSR ? SR_AtSupport(g_sr.current, bid, zoneTol) : true;
      bool atAsianLow = MathAbs(bid - g_asianLow) <= zoneTol;

      if((atVAL || atLVN || atSupp || atAsianLow) && trendOk)
      {
         double srSL = 0, srTP = 0;
         if(EnableSR && g_sr.current.valid)
         {
            srSL = SR_NearestSupportBelow(g_sr.current, bid);
            srTP = SR_NearestResistanceAbove(g_sr.current, bid);
         }
         ExecuteTrade(ORDER_TYPE_BUY, bid, atr, "ASIAN", pa.patternName, srSL, srTP);
      }
   }

   //--- SELL: price at VAH + bearish PA + not in uptrend + resistance nearby
   if(pa.direction == -1)
   {
      bool atVAH = FRVP_AtVAH(prof, ask, zoneTol);
      bool atLVN = FRVP_NearLVN(prof, ask, zoneTol) >= 0;
      bool trendOk = (!PA_RequireTrend || trendDir <= 0);
      bool atRes = EnableSR ? SR_AtResistance(g_sr.current, ask, zoneTol) : true;
      bool atAsianHigh = MathAbs(ask - g_asianHigh) <= zoneTol;

      if((atVAH || atLVN || atRes || atAsianHigh) && trendOk)
      {
         double srSL = 0, srTP = 0;
         if(EnableSR && g_sr.current.valid)
         {
            srSL = SR_NearestSupportAbove(g_sr.current, ask);
            srTP = SR_NearestResistanceBelow(g_sr.current, ask);
         }
         ExecuteTrade(ORDER_TYPE_SELL, ask, atr, "ASIAN", pa.patternName, srSL, srTP);
      }
   }
}

//+------------------------------------------------------------------+
//| LONDON SESSION: Breakout with FRVP confirmation                  |
//| Trade breakouts from Asian range with BOS at FRVP levels         |
//+------------------------------------------------------------------+
void CheckLondonEntry(int trendDir)
{
   if(!g_asianRangeReady || g_asianHigh <= 0 || g_asianLow <= 0) return;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, EntryTF, 0, 15, rates) < 10) return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double atr = g_atrValue;
   if(atr <= 0) return;

   FRVPResult prof = g_frvp.current;
   double zoneTol = atr * FRVP_ZoneTolATR;

   //--- Detect breakout from Asian range
   int breakDir = 0;
   int breakBar = -1;

   for(int c = 1; c <= 8; c++)
   {
      if(c >= ArraySize(rates)) break;
      if(rates[c].close > g_asianHigh && rates[c].close > rates[c].open)
      { breakDir = 1; breakBar = c; break; }
      if(rates[c].close < g_asianLow && rates[c].close < rates[c].open)
      { breakDir = -1; breakBar = c; break; }
   }
   if(breakDir == 0) return;

   //--- Look for retest after breakout
   for(int c = breakBar - 1; c >= 1 && c > breakBar - 5; c--)
   {
      if(c <= 0 || c >= ArraySize(rates)) continue;

      PASignal pa = PA_DetectPinBar(rates[c], rates[c + 1], atr, PA_MinWickATR, PA_WickBodyRatio);
      if(pa.direction == 0)
         pa = PA_DetectEngulfing(rates[c], rates[c + 1], atr, PA_MinBodyATR);

      if(breakDir == 1) // Bull breakout
      {
         if(pa.direction == +1 && rates[c].close > g_asianHigh)
         {
            //--- Bonus: price is at a FRVP zone (VAL support or HVN)
            bool frvpConfirm = FRVP_AtVAL(prof, bid, zoneTol * 2) ||
                               FRVP_NearHVN(prof, bid, zoneTol * 2) >= 0 ||
                               bid <= prof.vah; // inside VA = acceptable

            bool trendOk = (!PA_RequireTrend || trendDir >= 0);

            if(frvpConfirm && trendOk)
            {
               double srSL = 0, srTP = 0;
               if(EnableSR && g_sr.current.valid)
               {
                  srSL = SR_NearestSupportBelow(g_sr.current, bid);
                  srTP = SR_NearestResistanceAbove(g_sr.current, bid);
               }
               ExecuteTrade(ORDER_TYPE_BUY, ask, atr, "LONDON", pa.patternName, srSL, srTP);
               return;
            }
         }
      }
      else if(breakDir == -1) // Bear breakout
      {
         if(pa.direction == -1 && rates[c].close < g_asianLow)
         {
            bool frvpConfirm = FRVP_AtVAH(prof, ask, zoneTol * 2) ||
                               FRVP_NearHVN(prof, ask, zoneTol * 2) >= 0 ||
                               ask >= prof.val;

            bool trendOk = (!PA_RequireTrend || trendDir <= 0);

            if(frvpConfirm && trendOk)
            {
               double srSL = 0, srTP = 0;
               if(EnableSR && g_sr.current.valid)
               {
                  srSL = SR_NearestSupportAbove(g_sr.current, ask);
                  srTP = SR_NearestResistanceBelow(g_sr.current, ask);
               }
               ExecuteTrade(ORDER_TYPE_SELL, bid, atr, "LONDON", pa.patternName, srSL, srTP);
               return;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| NY SESSION: Liquidity sweep + FRVP zone reversal                 |
//| Sweep highs/lows, then reverse at FRVP POC/VAH/VAL with PA      |
//+------------------------------------------------------------------+
void CheckNYEntry(int trendDir)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, EntryTF, 0, 20, rates) < 10) return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double atr = g_atrValue;
   if(atr <= 0) return;

   FRVPResult prof = g_frvp.current;
   double zoneTol = atr * FRVP_ZoneTolATR;

   //--- Detect sweep: wick above/below recent high/low with rejection
   int bar = 1; // last closed
   if(bar >= ArraySize(rates)) return;

   double barHigh = rates[bar].high;
   double barLow  = rates[bar].low;
   double barClose = rates[bar].close;
   double barOpen  = rates[bar].open;
   double wickUp   = barHigh - MathMax(barClose, barOpen);
   double wickDown = MathMin(barClose, barOpen) - barLow;
   double body     = MathAbs(barClose - barOpen);
   double range    = barHigh - barLow;

   if(range <= 0) return;

   //--- Bullish sweep: long lower wick (swept lows) + rejection
   bool bullSweep = (wickDown >= atr * 0.3 && wickDown >= body * 1.5 && barClose > barOpen);

   //--- Bearish sweep: long upper wick + rejection
   bool bearSweep = (wickUp >= atr * 0.3 && wickUp >= body * 1.5 && barClose < barOpen);

   //--- Check if sweep targets FRVP zone
   if(bullSweep)
   {
      //--- Price swept below and is now at/below VAL or POC
      bool atPOC  = FRVP_AtPOC(prof, bid, zoneTol * 2);
      bool atVAL  = FRVP_AtVAL(prof, bid, zoneTol * 2);
      bool trendOk = (!PA_RequireTrend || trendDir >= 0);

      //--- Also: PA confirmation from the bar itself
      PASignal pa = PA_DetectPinBar(rates[bar], rates[bar + 1], atr, PA_MinWickATR, PA_WickBodyRatio);

      if((atPOC || atVAL || pa.direction == +1) && trendOk)
      {
         double srSL = 0, srTP = 0;
         if(EnableSR && g_sr.current.valid)
         {
            srSL = SR_NearestSupportBelow(g_sr.current, bid);
            srTP = SR_NearestResistanceAbove(g_sr.current, bid);
         }
         ExecuteTrade(ORDER_TYPE_BUY, ask, atr, "NY", "Sweep_BULL+" + (atPOC ? "POC" : atVAL ? "VAL" : pa.patternName), srSL, srTP);
         return;
      }
   }

   if(bearSweep)
   {
      bool atPOC  = FRVP_AtPOC(prof, ask, zoneTol * 2);
      bool atVAH  = FRVP_AtVAH(prof, ask, zoneTol * 2);
      bool trendOk = (!PA_RequireTrend || trendDir <= 0);

      PASignal pa = PA_DetectPinBar(rates[bar], rates[bar + 1], atr, PA_MinWickATR, PA_WickBodyRatio);

      if((atPOC || atVAH || pa.direction == -1) && trendOk)
      {
         double srSL = 0, srTP = 0;
         if(EnableSR && g_sr.current.valid)
         {
            srSL = SR_NearestSupportAbove(g_sr.current, ask);
            srTP = SR_NearestResistanceBelow(g_sr.current, ask);
         }
         ExecuteTrade(ORDER_TYPE_SELL, bid, atr, "NY", "Sweep_BEAR+" + (atPOC ? "POC" : atVAH ? "VAH" : pa.patternName), srSL, srTP);
         return;
      }
   }

   //--- Also: direct FRVP zone reaction (no sweep required for POC)
   PASignal pa = PA_AggregateScore(rates, 20, atr,
                                    prof.vah, prof.val,
                                    PA_MinWickATR, PA_WickBodyRatio,
                                    PA_MinBodyATR, PA_MinMoveATR);

   if(pa.strength >= 3) // at least medium-strength PA
   {
      if(pa.direction == +1 && (FRVP_AtPOC(prof, bid, zoneTol) || SR_AtSupport(g_sr.current, bid, zoneTol)))
      {
         bool trendOk = (!PA_RequireTrend || trendDir >= 0);
         if(trendOk)
         {
            double srSL = 0, srTP = 0;
            if(EnableSR && g_sr.current.valid)
            {
               srSL = SR_NearestSupportBelow(g_sr.current, bid);
               srTP = SR_NearestResistanceAbove(g_sr.current, bid);
            }
            ExecuteTrade(ORDER_TYPE_BUY, ask, atr, "NY_POC", pa.patternName, srSL, srTP);
         }
      }
      else if(pa.direction == -1 && (FRVP_AtPOC(prof, ask, zoneTol) || SR_AtResistance(g_sr.current, ask, zoneTol)))
      {
         bool trendOk = (!PA_RequireTrend || trendDir <= 0);
         if(trendOk)
         {
            double srSL = 0, srTP = 0;
            if(EnableSR && g_sr.current.valid)
            {
               srSL = SR_NearestSupportAbove(g_sr.current, ask);
               srTP = SR_NearestResistanceBelow(g_sr.current, ask);
            }
            ExecuteTrade(ORDER_TYPE_SELL, bid, atr, "NY_POC", pa.patternName, srSL, srTP);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Tick-flow proxy: classify each tick as buy/sell (last-delta rule)|
//+------------------------------------------------------------------+
void AccumulateTickFlow()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(bid <= 0) return;

   datetime now = TimeTradeServer();
   datetime nowMin = now - (now % 60);

   if(g_lastFlowBid <= 0) { g_lastFlowBid = bid; return; }
   int dir = (bid > g_lastFlowBid) ? +1 : (bid < g_lastFlowBid ? -1 : 0);
   g_lastFlowBid = bid;
   if(dir == 0) return;

   if(g_flowHead < 0 || g_flowMinute[g_flowHead] != nowMin)
   {
      g_flowHead = (g_flowHead + 1) % FLOW_BINS;
      g_flowMinute[g_flowHead] = nowMin;
      g_flowBuy[g_flowHead] = 0;
      g_flowSell[g_flowHead] = 0;
   }
   if(dir > 0) g_flowBuy[g_flowHead] += 1.0;
   else        g_flowSell[g_flowHead] += 1.0;
}

//+------------------------------------------------------------------+
//| Fraction of buying pressure over the last N minutes (0..1)       |
//+------------------------------------------------------------------+
double TF_BuyRatio(int windowMinutes)
{
   if(g_flowHead < 0) return 0.5;
   datetime now = TimeTradeServer();
   datetime cutoff = now - (datetime)(windowMinutes * 60);
   double buy = 0, sell = 0;
   for(int i = 0; i < FLOW_BINS; i++)
   {
      if(g_flowMinute[i] == 0 || g_flowMinute[i] < cutoff) continue;
      buy  += g_flowBuy[i];
      sell += g_flowSell[i];
   }
   double tot = buy + sell;
   if(tot <= 0) return 0.5;
   return buy / tot;
}

//+------------------------------------------------------------------+
//| Build volume profile of TODAY'S Asian session only               |
//| Produces Asia-POC / VAH / VAL used by London sweep entries       |
//+------------------------------------------------------------------+
void ComputeAsiaProfile()
{
   g_asiaProfileValid = false;
   g_asiaPOC = 0; g_asiaVAH = 0; g_asiaVAL = 0;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, EntryTF, 0, 300, rates) < 10) return;

   double bucket = (FRVP_BucketPips > 0) ? FRVP_BucketPips : 0.50;
   double lo = 1e9, hi = 0;
   int n = 0;

   //--- Pass 1: find Asian-window price extent
   for(int i = 0; i < ArraySize(rates); i++)
   {
      MqlDateTime dt;
      TimeToStruct(rates[i].time, dt);
      int hourGMT = dt.hour - g_brokerGMTOffset;
      if(hourGMT < 0) hourGMT += 24;

      bool inAsian = (hourGMT == Asian_StartH && dt.min >= Asian_StartM) ||
                     (hourGMT > Asian_StartH && hourGMT < Asian_EndH) ||
                     (hourGMT == Asian_EndH && dt.min <= Asian_EndM);
      if(!inAsian) continue;
      if(rates[i].low  < lo) lo = rates[i].low;
      if(rates[i].high > hi) hi = rates[i].high;
      n++;
   }
   if(n < 3 || hi <= lo) return;

   //--- Pass 2: histogram, spread each bar's tick volume across its range
   int nb = (int)MathCeil((hi - lo) / bucket) + 1;
   if(nb < 2) return;
   double volA[];
   ArrayResize(volA, nb);
   ArrayInitialize(volA, 0.0);

   for(int i = 0; i < ArraySize(rates); i++)
   {
      MqlDateTime dt;
      TimeToStruct(rates[i].time, dt);
      int hourGMT = dt.hour - g_brokerGMTOffset;
      if(hourGMT < 0) hourGMT += 24;

      bool inAsian = (hourGMT == Asian_StartH && dt.min >= Asian_StartM) ||
                     (hourGMT > Asian_StartH && hourGMT < Asian_EndH) ||
                     (hourGMT == Asian_EndH && dt.min <= Asian_EndM);
      if(!inAsian) continue;

      double vol = (rates[i].tick_volume > 0) ? (double)rates[i].tick_volume : 1.0;
      int b0 = (int)MathFloor((rates[i].low  - lo) / bucket);
      int b1 = (int)MathFloor((rates[i].high - lo) / bucket);
      if(b0 < 0) b0 = 0;
      if(b1 >= nb) b1 = nb - 1;
      int span = b1 - b0 + 1;
      double per = vol / span;
      for(int b = b0; b <= b1; b++) volA[b] += per;
   }

   //--- POC
   int pocIdx = 0;
   double total = 0;
   for(int b = 0; b < nb; b++) { total += volA[b]; if(volA[b] > volA[pocIdx]) pocIdx = b; }
   if(total <= 0) return;

   //--- Value area: expand from POC taking the fatter neighbour
   double vaTarget = total * FRVP_ValueAreaPct / 100.0;
   double vaVol = volA[pocIdx];
   int loIdx = pocIdx, hiIdx = pocIdx;
   while(vaVol < vaTarget && (loIdx > 0 || hiIdx < nb - 1))
   {
      double dn = (loIdx > 0)        ? volA[loIdx - 1] : -1;
      double up = (hiIdx < nb - 1)   ? volA[hiIdx + 1] : -1;
      if(up >= dn) { hiIdx++; vaVol += volA[hiIdx]; }
      else         { loIdx--; vaVol += volA[loIdx]; }
   }

   g_asiaPOC = NormalizeDouble(lo + (pocIdx + 0.5) * bucket, _Digits);
   g_asiaVAH = NormalizeDouble(lo + (hiIdx + 1.0) * bucket, _Digits);
   g_asiaVAL = NormalizeDouble(lo + loIdx * bucket, _Digits);
   g_asiaProfileValid = true;

   Print("AsiaVP | Range=", DoubleToString(lo, 2), "-", DoubleToString(hi, 2),
         " POC=", DoubleToString(g_asiaPOC, 2),
         " VAH=", DoubleToString(g_asiaVAH, 2),
         " VAL=", DoubleToString(g_asiaVAL, 2));
}

//+------------------------------------------------------------------+
//| LONDON SWEEP ENTRY (Asia-VP grab & reverse, Shadow Intel style)  |
//| Sweep of Asian high/low that closes back inside = fade toward    |
//| Asia value area. Confirmed by tick-flow pressure.                |
//| Returns true if a signal was processed this bar.                 |
//+------------------------------------------------------------------+
bool CheckLondonSweepEntry(int trendDir)
{
   if(!g_asianRangeReady || !g_asiaProfileValid) return false;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, EntryTF, 0, 8, rates) < 4) return false;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double atr = g_atrValue;
   if(atr <= 0) return false;

   //--- Range quality gate: dead Asian sessions are not tradeable
   double asianRange = g_asianHigh - g_asianLow;
   if(asianRange < AsiaVP_MinRangeATR * atr) return false;

   //--- Scan last 3 closed bars for a sweep-and-reject of Asian extremes
   for(int c = 1; c <= 3 && c < ArraySize(rates); c++)
   {
      //--- BEARISH grab: pushed above Asian high, closed back inside
      if(rates[c].high > g_asianHigh && rates[c].close < g_asianHigh && rates[c].close < rates[c].open)
      {
         bool zoneOk = (ask >= g_asiaVAH - atr * FRVP_ZoneTolATR) || (bid <= g_asiaVAH);
         bool flowOk = (!AsiaVP_UseFlow) || (TF_BuyRatio(AsiaVP_FlowWinMin) < 0.45);
         bool trendOk = (!PA_RequireTrend || trendDir <= 0);
         if(zoneOk && flowOk && trendOk)
         {
            //--- SL beyond sweep extreme, TP at Asia VAL / POC
            double tpZone = (g_asiaVAL < ask - atr) ? g_asiaVAL : g_asiaPOC;
            ExecuteTrade(ORDER_TYPE_SELL, bid, atr, "LON_SWEEP", "AsiaVP_SweepHIGH",
                         rates[c].high, tpZone);
            return true;
         }
      }

      //--- BULLISH grab: pushed below Asian low, closed back inside
      if(rates[c].low < g_asianLow && rates[c].close > g_asianLow && rates[c].close > rates[c].open)
      {
         bool zoneOk = (bid <= g_asiaVAL + atr * FRVP_ZoneTolATR) || (bid >= g_asiaVAL);
         bool flowOk = (!AsiaVP_UseFlow) || (TF_BuyRatio(AsiaVP_FlowWinMin) > 0.55);
         bool trendOk = (!PA_RequireTrend || trendDir >= 0);
         if(zoneOk && flowOk && trendOk)
         {
            double tpZone = (g_asiaVAH > bid + atr) ? g_asiaVAH : g_asiaPOC;
            ExecuteTrade(ORDER_TYPE_BUY, ask, atr, "LON_SWEEP", "AsiaVP_SweepLOW",
                         rates[c].low, tpZone);
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| VP-PRO ENTRY: Weekly VP + Hard S/D + Order Flow confluence       |
//| Syndicate / Shadow Intel style:                                  |
//| 1. Weekly POC = buy zone / sell zone boundary                    |
//| 2. Hard S/D zone must be at/near a VP level                      |
//| 3. Tick-flow confirms direction                                  |
//| 4. Enter at zone edge, TP at opposing VP level                   |
//+------------------------------------------------------------------+
bool CheckVPProEntry(int trendDir)
{
   if(!g_wvp.valid) return false;
   if(!g_frvp.current.valid) return false; // need FRVP too for confluence

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, EntryTF, 0, 8, rates) < 4) return false;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double atr = g_atrValue;
   if(atr <= 0) return false;

   double tol = VPPro_ZoneTolATR * atr;

   //--- VP levels
   double wPOC = g_wvp.poc;  // Weekly POC
   double wVAH = g_wvp.vah;  // Weekly VAH
   double wVAL = g_wvp.val;  // Weekly VAL

   //--- FRVP levels for additional confluence
   FRVPResult frvp = g_frvp.current;

   //=== BUY: price in buy zone (near weekly POC or VAL) + demand zone + flow ===
   bool nearPOC_buy = MathAbs(bid - wPOC) <= tol;
   bool nearVAL_buy = MathAbs(bid - wVAL) <= tol;
   bool inBuyZone   = bid >= wVAL - tol && bid <= wPOC + tol;

   if(nearPOC_buy || nearVAL_buy || inBuyZone)
   {
      //--- Hard S/D: check for demand zone nearby
      bool hasDemand = GetNearestDemandZone(bid, VPPro_SDProxATR, atr, g_swingBullish[0]);
      bool sdNearDemand = false;
      if(hasDemand)
      {
         for(int i = 0; i < g_swingBullishTotal; i++)
         {
            if(g_swingBullish[i].strength < VPPro_MinSDStr) continue;
            if(bid >= g_swingBullish[i].priceLow - tol &&
               bid <= g_swingBullish[i].priceHigh + tol * 2)
            { sdNearDemand = true; break; }
         }
      }
      //--- Also accept if price is at FRVP VAL (additional confluence)
      bool frvpConfirm = frvp.valid && (FRVP_AtVAL(frvp, bid, tol) || FRVP_AtPOC(frvp, bid, tol));

      //--- Flow confirmation
      bool flowOk = (!VPPro_RequireFlow) || (TF_BuyRatio(VPPro_FlowWinMin) >= VPPro_FlowThresh);

      //--- Trend filter
      bool trendOk = (!PA_RequireTrend || trendDir >= 0);

      //--- Need at least S/D zone OR FRVP confirmation (don't trade blind)
      bool zoneConfirmed = sdNearDemand || frvpConfirm;

      if(zoneConfirmed && flowOk && trendOk)
      {
         //--- TP = next VP level up (weekly VAH or FRVP VAH)
         double tpLevel = wVAH;
         if(frvp.valid && frvp.vah > ask && frvp.vah < wVAH)
            tpLevel = frvp.vah; // closer target

         //--- SL below the demand zone or below weekly VAL
         double slLevel = wVAL;
         if(sdNearDemand)
         {
            for(int i = 0; i < g_swingBullishTotal; i++)
            {
               if(g_swingBullish[i].strength < VPPro_MinSDStr) continue;
               if(bid >= g_swingBullish[i].priceLow - tol &&
                  bid <= g_swingBullish[i].priceHigh + tol * 2)
               { slLevel = g_swingBullish[i].priceLow - atr * 0.3; break; }
            }
         }

         ExecuteTrade(ORDER_TYPE_BUY, ask, atr, "VPPRO",
                      "VPBuy_POC" + (sdNearDemand ? "+SD" : "") + (flowOk ? "+Flow" : ""),
                      slLevel, tpLevel);
         return true;
      }
   }

   //=== SELL: price in sell zone (near weekly POC or VAH) + supply zone + flow ===
   bool nearPOC_sell = MathAbs(ask - wPOC) <= tol;
   bool nearVAH_sell = MathAbs(ask - wVAH) <= tol;
   bool inSellZone   = ask >= wPOC - tol && ask <= wVAH + tol;

   if(nearPOC_sell || nearVAH_sell || inSellZone)
   {
      //--- Hard S/D: check for supply zone nearby
      bool hasSupply = GetNearestSupplyZone(ask, VPPro_SDProxATR, atr, g_swingBearish[0]);
      bool sdNearSupply = false;
      if(hasSupply)
      {
         for(int i = 0; i < g_swingBearishTotal; i++)
         {
            if(g_swingBearish[i].strength < VPPro_MinSDStr) continue;
            if(ask >= g_swingBearish[i].priceLow - tol * 2 &&
               ask <= g_swingBearish[i].priceHigh + tol)
            { sdNearSupply = true; break; }
         }
      }
      //--- Also accept if price is at FRVP VAH (additional confluence)
      bool frvpConfirm = frvp.valid && (FRVP_AtVAH(frvp, ask, tol) || FRVP_AtPOC(frvp, ask, tol));

      //--- Flow confirmation: need sell pressure
      bool flowOk = (!VPPro_RequireFlow) || (TF_BuyRatio(VPPro_FlowWinMin) <= (1.0 - VPPro_FlowThresh));

      //--- Trend filter
      bool trendOk = (!PA_RequireTrend || trendDir <= 0);

      bool zoneConfirmed = sdNearSupply || frvpConfirm;

      if(zoneConfirmed && flowOk && trendOk)
      {
         //--- TP = next VP level down (weekly VAL or FRVP VAL)
         double tpLevel = wVAL;
         if(frvp.valid && frvp.val < bid && frvp.val > wVAL)
            tpLevel = frvp.val; // closer target

         //--- SL above the supply zone or above weekly VAH
         double slLevel = wVAH;
         if(sdNearSupply)
         {
            for(int i = 0; i < g_swingBearishTotal; i++)
            {
               if(g_swingBearish[i].strength < VPPro_MinSDStr) continue;
               if(ask >= g_swingBearish[i].priceLow - tol * 2 &&
                  ask <= g_swingBearish[i].priceHigh + tol)
               { slLevel = g_swingBearish[i].priceHigh + atr * 0.3; break; }
            }
         }

         ExecuteTrade(ORDER_TYPE_SELL, bid, atr, "VPPRO",
                      "VPSell_POC" + (sdNearSupply ? "+SD" : "") + (flowOk ? "+Flow" : ""),
                      slLevel, tpLevel);
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Execute a trade with risk-based sizing                           |
//| srSL/srTP = S/R-derived levels (0 = use ATR-based defaults)      |
//+------------------------------------------------------------------+
void ExecuteTrade(int orderType, double entryPrice, double atr,
                  string sessionTag, string paTag,
                  double srSL = 0, double srTP = 0)
{
   if(atr <= 0) return;

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double slDist = atr * Min_SL_ATR;
   if(slDist < Min_SL_ATR * atr) slDist = Min_SL_ATR * atr;

   double tpDist = atr * 2.0;
   FRVPResult prof = g_frvp.current;

   if(orderType == ORDER_TYPE_BUY)
   {
      double sl = entryPrice - slDist;
      double tp = entryPrice + tpDist;

      //--- S/R SL: place below nearest support
      if(srSL > 0 && srSL < entryPrice)
      {
         double srDist = entryPrice - srSL;
         if(srDist >= Min_SL_ATR * atr && srDist <= atr * 3.0)
            sl = srSL - atr * 0.2; // buffer below support
      }

      //--- S/R TP: target nearest resistance above
      if(srTP > 0 && srTP > entryPrice)
      {
         double srTDDist = srTP - entryPrice;
         if(srTDDist >= slDist * 1.2 && srTDDist <= atr * 5.0)
            tp = srTP;
      }

      //--- Fallback: FRVP zone as TP
      if(tp == entryPrice + tpDist && prof.valid)
      {
         double nearestZone = prof.vah;
         if(prof.poc > entryPrice + slDist * 1.5)
            nearestZone = prof.poc;
         if(nearestZone > entryPrice + slDist * 0.5 && nearestZone < entryPrice + atr * 4.0)
            tp = nearestZone;
      }

      //--- Ensure min 1.5:1 RR
      slDist = entryPrice - sl;
      if(tp - entryPrice < slDist * 2.0) tp = entryPrice + slDist * 2.0;

      sl = NormalizeDouble(sl, digits);
      tp = NormalizeDouble(tp, digits);

      double lot = CalcLotSizeRisk(entryPrice - sl, RiskPerTradePct);
      if(lot <= 0) return;

      if(VerifyTrade(ORDER_TYPE_BUY, entryPrice, sl, tp, lot))
      {
         string comment = CommentPrefix + "_FRVP_BUY_" + sessionTag;
         if(OpenOrder(ORDER_TYPE_BUY, lot, entryPrice, sl, tp, comment))
         {
            g_stats.tradeCount++;
            g_stats.sessionTradeCount++;
            g_lastTradeTime = TimeCurrent();
            Print("FRVP BUY ", sessionTag, ": ", paTag,
                  " price=", DoubleToString(entryPrice, digits),
                  " SL=", DoubleToString(sl, digits),
                  " TP=", DoubleToString(tp, digits),
                  " POC=", DoubleToString(prof.poc, digits),
                  " SR_SL=", DoubleToString(srSL, digits),
                  " SR_TP=", DoubleToString(srTP, digits));
         }
      }
   }
   else if(orderType == ORDER_TYPE_SELL)
   {
      double sl = entryPrice + slDist;
      double tp = entryPrice - tpDist;

      //--- S/R SL: place above nearest resistance
      if(srSL > 0 && srSL > entryPrice)
      {
         double srDist = srSL - entryPrice;
         if(srDist >= Min_SL_ATR * atr && srDist <= atr * 3.0)
            sl = srSL + atr * 0.2; // buffer above resistance
      }

      //--- S/R TP: target nearest support below
      if(srTP > 0 && srTP < entryPrice)
      {
         double srTDDist = entryPrice - srTP;
         if(srTDDist >= slDist * 1.2 && srTDDist <= atr * 5.0)
            tp = srTP;
      }

      //--- Fallback: FRVP zone as TP
      if(tp == entryPrice - tpDist && prof.valid)
      {
         double nearestZone = prof.val;
         if(prof.poc < entryPrice - slDist * 1.5)
            nearestZone = prof.poc;
         if(nearestZone < entryPrice - slDist * 0.5 && nearestZone > entryPrice - atr * 4.0)
            tp = nearestZone;
      }

      slDist = sl - entryPrice;
      if(entryPrice - tp < slDist * 2.0) tp = entryPrice - slDist * 2.0;

      sl = NormalizeDouble(sl, digits);
      tp = NormalizeDouble(tp, digits);

      double lot = CalcLotSizeRisk(sl - entryPrice, RiskPerTradePct);
      if(lot <= 0) return;

      if(VerifyTrade(ORDER_TYPE_SELL, entryPrice, sl, tp, lot))
      {
         string comment = CommentPrefix + "_FRVP_SELL_" + sessionTag;
         if(OpenOrder(ORDER_TYPE_SELL, lot, entryPrice, sl, tp, comment))
         {
            g_stats.tradeCount++;
            g_stats.sessionTradeCount++;
            g_lastTradeTime = TimeCurrent();
            Print("FRVP SELL ", sessionTag, ": ", paTag,
                  " price=", DoubleToString(entryPrice, digits),
                  " SL=", DoubleToString(sl, digits),
                  " TP=", DoubleToString(tp, digits),
                  " POC=", DoubleToString(prof.poc, digits));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Track Asian range                                                |
//+------------------------------------------------------------------+
void TrackAsianRange()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, EntryTF, 0, 100, rates) < 20) return;

   g_asianHigh = 0;
   g_asianLow  = 1e9;
   g_asianRangeReady = false;
   int barsInSession = 0;

   for(int i = 0; i < ArraySize(rates); i++)
   {
      MqlDateTime dt;
      TimeToStruct(rates[i].time, dt);
      int hourGMT = dt.hour - g_brokerGMTOffset;
      if(hourGMT < 0) hourGMT += 24;
      int minuteGMT = dt.min;

      bool inAsian = false;
      if((hourGMT == Asian_StartH && minuteGMT >= Asian_StartM) ||
         (hourGMT > Asian_StartH && hourGMT < Asian_EndH) ||
         (hourGMT == Asian_EndH && minuteGMT <= Asian_EndM))
         inAsian = true;

      if(inAsian)
      {
         if(rates[i].high > g_asianHigh) g_asianHigh = rates[i].high;
         if(rates[i].low  < g_asianLow)  g_asianLow  = rates[i].low;
         barsInSession++;
      }
      else if(barsInSession > 0) break;
   }

   if(g_asianHigh > 0 && g_asianLow < 1e8 && barsInSession >= 3)
      g_asianRangeReady = true;
}

//+------------------------------------------------------------------+
//| Detect session levels                                            |
//+------------------------------------------------------------------+
void DetectSessionLevels()
{
   SessionType sess = GetCurrentSession();

   if(sess == SESS_ASIAN || sess == SESS_LONDON)
   {
      int hourGMT = GetGMTHour();
      int minuteGMT = GetGMTMin();
      bool asianOngoing = false;
      if((hourGMT == Asian_StartH && minuteGMT >= Asian_StartM) ||
         (hourGMT > Asian_StartH && hourGMT < Asian_EndH) ||
         (hourGMT == Asian_EndH && minuteGMT <= Asian_EndM))
         asianOngoing = true;

      if(!asianOngoing && g_asianSessionStart > 0)
      {
         TrackAsianRange();
         ComputeAsiaProfile();
         g_asianSessionStart = 0;
      }
      if(asianOngoing && g_asianSessionStart == 0)
      {
         MqlDateTime asianDt;
         TimeTradeServer(asianDt);
         g_asianSessionStart = StructToTime(asianDt);
         g_asianHigh = 0;
         g_asianLow  = 1e9;
         g_asianRangeReady = false;
      }
   }
}

//+------------------------------------------------------------------+
//| Update swing points                                              |
//+------------------------------------------------------------------+
void UpdateSwingPoints()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, EntryTF, 0, SwingLookback, rates) < 50) return;
   // Swing points are used for Asian range detection only now
}

//+------------------------------------------------------------------+
//| Utility functions                                                |
//+------------------------------------------------------------------+
int GetGMTHour()
{
   MqlDateTime dt;
   TimeTradeServer(dt);
   int gmtHour = dt.hour - g_brokerGMTOffset;
   if(gmtHour < 0) gmtHour += 24;
   return gmtHour;
}

int GetGMTMin()
{
   MqlDateTime dt;
   TimeTradeServer(dt);
   return dt.min;
}

SessionType GetCurrentSession()
{
   int hourGMT = GetGMTHour();
   int minuteGMT = GetGMTMin();
   int timeMinutes = hourGMT * 60 + minuteGMT;

   int asianStart  = Asian_StartH  * 60 + Asian_StartM;
   int asianEnd    = Asian_EndH    * 60 + Asian_EndM;
   int londonStart = London_StartH * 60 + London_StartM;
   int londonEnd   = London_EndH   * 60 + London_EndM;
   int nyStart     = NY_StartH     * 60 + NY_StartM;
   int nyEnd       = NY_EndH       * 60 + NY_EndM;

   if(asianEnd < asianStart) asianEnd += 1440;
   if(nyEnd < nyStart) nyEnd += 1440;

   int t = timeMinutes;
   if(asianEnd < asianStart && t < asianStart) t += 1440;
   if(t >= asianStart && t <= asianEnd) return SESS_ASIAN;

   t = timeMinutes;
   if(londonEnd < londonStart && t < londonStart) t += 1440;
   if(t >= londonStart && t <= londonEnd) return SESS_LONDON;

   t = timeMinutes;
   if(nyEnd < nyStart && t < nyStart) t += 1440;
   if(t >= nyStart && t <= nyEnd) return SESS_NY;

   return SESS_NONE;
}

string GetSessionName(SessionType s)
{
   switch(s)
   {
      case SESS_ASIAN:  return "ASIAN";
      case SESS_LONDON: return "LONDON";
      case SESS_NY:     return "NY";
      default:          return "OUTSIDE";
   }
}

double CalcATR(int period, ENUM_TIMEFRAMES tf)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, tf, 0, period + 1, rates) < period + 1)
   {
      Print("CalcATR: Not enough bars (", CopyRates(_Symbol, tf, 0, period + 1, rates), "/", period + 1, ")");
      return 0;
   }
   double sum = 0;
   for(int i = 1; i <= period; i++)
   {
      if(i >= ArraySize(rates)) break;
      double tr = MathMax(rates[i].high - rates[i].low,
                  MathMax(MathAbs(rates[i].high - rates[i-1].close),
                           MathAbs(rates[i].low - rates[i-1].close)));
      sum += tr;
   }
   double atr = sum / period;
   //--- Safety floor: minimum 1.0 pt ATR to prevent division by zero
   if(atr < 1.0)
   {
      Print("CalcATR: ATR too low (", DoubleToString(atr, 2), "), using floor 1.0");
      return 1.0;
   }
   return atr;
}

bool IsNewBar()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, EntryTF, 0, 1, rates) < 1) return false;
   if(rates[0].time != g_lastBarTime)
   {
      g_lastBarTime = rates[0].time;
      return true;
   }
   return false;
}

void ResetDaily()
{
   MqlDateTime dt;
   TimeTradeServer(dt);
   datetime today = dt.year * 10000 + dt.mon * 100 + dt.day;

   if(g_stats.lastResetTime != today)
   {
      g_stats.lastResetTime = today;
      g_stats.startingBalance = m_account.Balance();
      g_stats.tradeCount = 0;
      g_stats.sessionTradeCount = 0;
      g_stats.tradingStopped = false;
      g_stats.lastSession = SESS_NONE;
      g_asianSessionStart = 0;
      g_asianRangeReady = false;
      g_frvpRefreshCounter = FRVP_RefreshBars; // force recompute
      g_asiaProfileValid = false;
      g_flowHead = -1;
      g_lastFlowBid = 0;
      for(int fb = 0; fb < FLOW_BINS; fb++) { g_flowBuy[fb] = 0; g_flowSell[fb] = 0; g_flowMinute[fb] = 0; }
      g_wvpRefreshCounter = 0;
      if(EnableVPPro) WeeklyVP_Compute(g_wvp, _Symbol, VPPro_BucketPips, VPPro_VAAPct, g_brokerGMTOffset);
      Print("--- Daily reset. Balance: ", g_stats.startingBalance, " ---");
   }

   if(!g_stats.tradingStopped && g_stats.startingBalance > 0)
   {
      double ddPct = (g_stats.startingBalance - m_account.Equity()) / g_stats.startingBalance * 100.0;
      if(ddPct >= MaxDailyRiskPct)
      {
         g_stats.tradingStopped = true;
         Print("*** HARD STOP: MAX DAILY LOSS ", DoubleToString(ddPct, 2), "% — CLOSING ALL POSITIONS ***");
         CloseAllPositions("DAILY_LOSS_LIMIT");
      }
   }
}

//+------------------------------------------------------------------+
//| Position management                                              |
//+------------------------------------------------------------------+
void ManagePositions()
{
   if(!UseBreakEven && !UseTrailing) return;
   if(g_atrValue <= 0) return;

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl    = PositionGetDouble(POSITION_SL);
      double tp    = PositionGetDouble(POSITION_TP);
      long type    = PositionGetInteger(POSITION_TYPE);
      double curPrice = (type == POSITION_TYPE_BUY) ?
                        SymbolInfoDouble(_Symbol, SYMBOL_BID) :
                        SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      if(UseBreakEven)
      {
         double beDist = BE_ATR_Mult * g_atrValue;
         if(type == POSITION_TYPE_BUY)
         {
            if(curPrice >= entry + beDist && sl < entry)
               ModifySL(ticket, NormalizeDouble(entry + point * 5, digits));
         }
         else
         {
            if(curPrice <= entry - beDist && (sl > entry || sl == 0))
               ModifySL(ticket, NormalizeDouble(entry - point * 5, digits));
         }
      }

      if(UseTrailing)
      {
         double trailStart = TrailStart_ATR * g_atrValue;
         double trailStep  = TrailStep_ATR * g_atrValue;

         if(type == POSITION_TYPE_BUY)
         {
            double profitDist = curPrice - entry;
            if(profitDist >= trailStart)
            {
               double newSL = NormalizeDouble(curPrice - trailStep, digits);
               if(newSL > sl + point) ModifySL(ticket, newSL);
            }
         }
         else
         {
            double profitDist = entry - curPrice;
            if(profitDist >= trailStart)
            {
               double newSL = NormalizeDouble(curPrice + trailStep, digits);
               if(newSL < sl - point || sl == 0) ModifySL(ticket, newSL);
            }
         }
      }
   }
}

int CountOpenPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      count++;
   }
   return count;
}

void CloseAllPositions(string reason)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

      int type = (int)PositionGetInteger(POSITION_TYPE);
      int orderType = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      double price = (type == POSITION_TYPE_BUY) ?
                     SymbolInfoDouble(_Symbol, SYMBOL_BID) :
                     SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      MqlTradeRequest req = {};
      MqlTradeResult  res = {};
      req.action = TRADE_ACTION_DEAL;
      req.position = ticket;
      req.symbol = _Symbol;
      req.volume = PositionGetDouble(POSITION_VOLUME);
      req.type = (ENUM_ORDER_TYPE)orderType;
      req.price = price;
      req.deviation = MaxSlippagePts;
      req.comment = reason;
      req.magic = MagicNumber;
      req.type_filling = g_fillMode;
      if(!OrderSend(req, res))
         if(DebugMode) Print("CloseAll: failed, err=", GetLastError());
   }
}

double CalcLotSizeRisk(double slDist, double riskPct)
{
   if(slDist <= 0) return 0;
   if(g_atrValue > 0 && slDist < Min_SL_ATR * g_atrValue) slDist = Min_SL_ATR * g_atrValue;

   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickVal <= 0 || tickSize <= 0) return 0;

   double riskAmount = m_account.Balance() * riskPct / 100.0;
   double slTicks = slDist / tickSize;
   double lot = riskAmount / (slTicks * tickVal);
   lot = NormalizeDouble(lot, 2);

   double vstep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(vstep > 0) lot = MathFloor(lot / vstep + 1e-9) * vstep;

   double maxVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(price > 0)
   {
      double volCap = (m_account.Balance() / 10000.0) * 30000.0 / price;
      if(volCap < maxVol) maxVol = volCap;
   }
   if(vstep > 0) maxVol = MathFloor(maxVol / vstep) * vstep;

   double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double cappedLot = MathMax(minVol, MathMin(lot, maxVol));
   //--- Hard cap: never risk more than 1% on a single trade
   double hardCap = NormalizeDouble(m_account.Balance() / 10000.0 * 1.0, 2);
   if(vstep > 0) hardCap = MathFloor(hardCap / vstep + 1e-9) * vstep;
   if(hardCap >= minVol && hardCap < cappedLot) cappedLot = hardCap;
   //--- Safety cap: MaxLotSize from inputs
   if(cappedLot > MaxLotSize) cappedLot = MaxLotSize;
   return cappedLot;
}

bool VerifyTrade(int type, double price, double sl, double tp, double lot)
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   price = NormalizeDouble(price, digits);
   sl    = NormalizeDouble(sl, digits);
   tp    = NormalizeDouble(tp, digits);

   if(lot <= 0) return false;
   if(type == ORDER_TYPE_BUY && price < bid * 0.99) return false;
   if(type == ORDER_TYPE_SELL && price > ask * 1.01) return false;

   if(type == ORDER_TYPE_BUY) { if(sl >= price) return false; if(tp > 0 && tp <= price) return false; }
   if(type == ORDER_TYPE_SELL) { if(sl <= price) return false; if(tp > 0 && tp >= price) return false; }

   double slPips = MathAbs(price - sl);
   double tpPips = MathAbs(tp - price);
   double minDist = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if(slPips < minDist && slPips > 0) return false;
   if(tpPips < minDist && tpPips > 0) return false;

   return true;
}

bool OpenOrder(int type, double volume, double price, double sl, double tp, string comment)
{
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   price = NormalizeDouble(price, digits);
   sl    = NormalizeDouble(sl, digits);
   tp    = NormalizeDouble(tp, digits);

   if(!m_trade.PositionOpen(_Symbol, (ENUM_ORDER_TYPE)type, volume, price, sl, tp, comment))
   {
      Print("ORDER FAILED: ", comment, " err=", GetLastError(), " vol=", volume,
            " price=", price, " sl=", sl, " tp=", tp);
      return false;
   }
   Print("ORDER OK: ", comment, " vol=", volume, " price=", price, " sl=", sl, " tp=", tp);
   return true;
}

void ModifySL(ulong ticket, double newSL)
{
   if(PositionSelectByTicket(ticket))
   {
      double currentSL = PositionGetDouble(POSITION_SL);
      if(MathAbs(newSL - currentSL) < SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 2) return;
      double tp = PositionGetDouble(POSITION_TP);
      m_trade.PositionModify(ticket, newSL, tp);
   }
}

//+------------------------------------------------------------------+
//| Chart comment                                                    |
//+------------------------------------------------------------------+
string RepeatStr(string s, int n) { string r = ""; for(int i = 0; i < n; i++) r += s; return r; }

void UpdateComment()
{
   string sep = "\n" + RepeatStr("-", 30) + "\n";
   string info = "=== ScalpXAU v3.0 FRVP ===" + sep;
   info += "Symbol: " + _Symbol + " | TF: " + EnumToString(EntryTF) + "\n";
   info += "Balance: $" + DoubleToString(m_account.Balance(), 2);
   info += " | Equity: $" + DoubleToString(m_account.Equity(), 2);
   info += " | Spread: " + IntegerToString((int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD)) + "\n";

   double dd = 0;
   if(g_stats.startingBalance > 0)
      dd = (g_stats.startingBalance - m_account.Equity()) / g_stats.startingBalance * 100.0;
   info += "Today: " + IntegerToString(g_stats.tradeCount);
   info += " | Session: " + IntegerToString(g_stats.sessionTradeCount) + "/" + IntegerToString(MaxTradesPerSess);
   info += " | DD: " + DoubleToString(dd, 2) + "%" + sep;

   info += "Session: " + GetSessionName(g_currentSession) + "\n";
   if(g_asianRangeReady)
      info += "Asian Range: H=" + DoubleToString(g_asianHigh, 2) + " L=" + DoubleToString(g_asianLow, 2) + "\n";

   //--- Asia VP info
   if(EnableAsiaVP)
   {
      if(g_asiaProfileValid)
         info += "AsiaVP: POC=" + DoubleToString(g_asiaPOC, 2) +
                 " VAH=" + DoubleToString(g_asiaVAH, 2) +
                 " VAL=" + DoubleToString(g_asiaVAL, 2) + "\n";
      else
         info += "AsiaVP: waiting for Asian close...\n";
   }
   //--- VP-Pro info
   if(EnableVPPro && g_wvp.valid)
   {
      info += "VPPro: WPOC=" + DoubleToString(g_wvp.poc, 2) +
              " WVAH=" + DoubleToString(g_wvp.vah, 2) +
              " WVAL=" + DoubleToString(g_wvp.val, 2) + "\n";
      info += "SD Zones: D=" + IntegerToString(g_swingBullishTotal) +
              " S=" + IntegerToString(g_swingBearishTotal) + "\n";
   }
   info += "Flow(Buy%): " + DoubleToString(TF_BuyRatio(AsiaVP_FlowWinMin) * 100.0, 0) + "%\n";

   //--- FRVP info
   if(g_frvp.current.valid)
   {
      info += "FRVP: POC=" + DoubleToString(g_frvp.current.poc, 2);
      info += " VAH=" + DoubleToString(g_frvp.current.vah, 2);
      info += " VAL=" + DoubleToString(g_frvp.current.val, 2);
      info += " Zones=" + IntegerToString(g_frvp.current.zoneCount) + "\n";
   }
   else
   {
      info += "FRVP: computing...\n";
   }

   //--- S/R info
   if(EnableSR && g_sr.current.valid)
   {
      info += "S/R: S=" + IntegerToString(g_sr.current.supportCount);
      info += " R=" + IntegerToString(g_sr.current.resistanceCount);
      if(g_sr.current.supportCount > 0)
         info += " nearestS=" + DoubleToString(g_sr.current.supports[0].price, 2);
      if(g_sr.current.resistanceCount > 0)
         info += " nearestR=" + DoubleToString(g_sr.current.resistances[0].price, 2);
      info += "\n";
   }

   info += "ATR(14): " + DoubleToString(g_atrValue, 1) + "\n";
   info += "Open: " + IntegerToString(CountOpenPositions()) + sep;
   info += "Trailing: " + (UseTrailing ? "ON" : "OFF") + " | BE: " + (UseBreakEven ? "ON" : "OFF") + "\n";

   if(g_stats.tradingStopped) info += "*** TRADING STOPPED (daily loss limit) ***\n";
   if(g_stats.sessTradingStopped) info += "*** SESSION STOPPED (session DD limit) ***\n";

   Comment(info);
}
//+------------------------------------------------------------------+
