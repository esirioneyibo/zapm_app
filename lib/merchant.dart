import 'dart:math';
import 'dart:convert';
import "package:hex/hex.dart";
import 'package:decimal/decimal.dart';
import 'package:crypto/crypto.dart';
import 'package:socket_io_client/socket_io_client.dart';

import 'prefs.dart';
import 'utils.dart';

class ClaimCode {
  final Decimal amount;
  final String token;
  final String secret;

  ClaimCode({this.amount, this.token, this.secret});

  String getAddressIfJsonMatches(Map<String, dynamic> json) {
    if (token == json["token"] && secret == json["secret"])
      return json["address"];
    return null;
  }

  factory ClaimCode.generate(Decimal _amount) {
    return ClaimCode(
      amount: _amount,
      token: HEX.encode(secureRandom(count: 8)),
      secret: HEX.encode(secureRandom(count: 16))
    );
  }
}

class Rates {
  final Decimal merchantRate;
  final Decimal customerRate;
  final String settlementAddress;

  Rates({this.merchantRate, this.customerRate, this.settlementAddress});
}

class Bank {
  final String token;
  final String accountNumber;
  final bool defaultAccount;

  Bank({this.token, this.accountNumber, this.defaultAccount});
}

class Settlement {
  final String token;
  final Decimal amount;
  final Decimal amountReceive;
  final String bankAccount;
  final String txid;
  final String status;

  Settlement({this.token, this.amount, this.amountReceive, this.bankAccount, this.txid, this.status});
}

class SettlementResult {
  final Settlement settlement;
  final String error;

  SettlementResult(this.settlement, this.error);
}

String claimCodeUri(ClaimCode claimCode) {
  return "claimcode:${claimCode.token}?secret=${claimCode.secret}";
}

List<int> secureRandom({count: 32}) {
  var random = Random.secure();
  return List<int>.generate(count, (i) => random.nextInt(256));
}

String createHmacSig(String secret, String message) {
  var secretBytes = utf8.encode(secret);
  var messageBytes = utf8.encode(message);
  var hmac = Hmac(sha256, secretBytes);
  var digest = hmac.convert(messageBytes);
  return base64.encode(digest.bytes);
}

class NoApiKeyException implements Exception {}

void checkApiKey(String apikey, String apisecret) {
  if (apikey == null)
    throw NoApiKeyException();
  if (apisecret == null)
    throw NoApiKeyException();
}

Future<ClaimCode> merchantRegister(Decimal amount, int amountInt) async {
  var claimCode = ClaimCode.generate(amount);
  var baseUrl = await Prefs.apiserverGet();
  var url = baseUrl + "register";
  var apikey = await Prefs.apikeyGet();
  var apisecret = await Prefs.apisecretGet();
  checkApiKey(apikey, apisecret);
  var nonce = DateTime.now().toUtc().millisecondsSinceEpoch / 1000;
  var body = jsonEncode({"api_key": apikey, "nonce": nonce, "token": claimCode.token, "amount": amountInt});
  var sig = createHmacSig(apisecret, body);
  var response = await post(url, body, extraHeaders: {"X-Signature": sig});
  if (response.statusCode == 200) {
    return claimCode;
  }
  return null;
}

Future<String> merchantCheck(ClaimCode claimCode) async {
  var baseUrl = await Prefs.apiserverGet();
  var url = baseUrl + "check";
  var apikey = await Prefs.apikeyGet();
  var apisecret = await Prefs.apisecretGet();
  checkApiKey(apikey, apisecret);
  var nonce = DateTime.now().toUtc().millisecondsSinceEpoch / 1000;
  var body = jsonEncode({"api_key": apikey, "nonce": nonce, "token": claimCode.token});
  var sig = createHmacSig(apisecret, body);
  var response = await post(url, body, extraHeaders: {"X-Signature": sig});
  if (response.statusCode == 200) {
    return claimCode.getAddressIfJsonMatches(json.decode(response.body));
  }
  return null;
}

Future<bool> merchantClaim(ClaimCode claimCode, String address) async {
  var baseUrl = await Prefs.apiserverGet();
  var url = baseUrl + "claim";
  var body = jsonEncode({"token": claimCode.token, "secret": claimCode.secret, "address": address});
  var response = await post(url, body);
  if (response.statusCode == 200) {
    return true;
  }
  return false;
}

Future<bool> merchantWatch(String address) async {
  var baseUrl = await Prefs.apiserverGet();
  var url = baseUrl + "watch";
  var apikey = await Prefs.apikeyGet();
  var apisecret = await Prefs.apisecretGet();
  checkApiKey(apikey, apisecret);
  var nonce = DateTime.now().toUtc().millisecondsSinceEpoch / 1000;
  var body = jsonEncode({"api_key": apikey, "nonce": nonce, "address": address});
  var sig = createHmacSig(apisecret, body);
  var response = await post(url, body, extraHeaders: {"X-Signature": sig});
  if (response.statusCode == 200) {
    return true;
  }
  return false;
}

Future<bool> merchantWalletAddress(String address) async {
  var baseUrl = await Prefs.apiserverGet();
  var url = baseUrl + "wallet_address";
  var apikey = await Prefs.apikeyGet();
  var apisecret = await Prefs.apisecretGet();
  checkApiKey(apikey, apisecret);
  var nonce = DateTime.now().toUtc().millisecondsSinceEpoch / 1000;
  var body = jsonEncode({"api_key": apikey, "nonce": nonce, "address": address});
  var sig = createHmacSig(apisecret, body);
  var response = await post(url, body, extraHeaders: {"X-Signature": sig});
  if (response.statusCode == 200) {
    return true;
  }
  return false;
}

Future<bool> merchantTx() async {
  var baseUrl = await Prefs.apiserverGet();
  var url = baseUrl + "merchanttx";
  var apikey = await Prefs.apikeyGet();
  var apisecret = await Prefs.apisecretGet();
  checkApiKey(apikey, apisecret);
  var nonce = DateTime.now().toUtc().millisecondsSinceEpoch / 1000;
  var body = jsonEncode({"api_key": apikey, "nonce": nonce,});
  var sig = createHmacSig(apisecret, body);
  var response = await post(url, body, extraHeaders: {"X-Signature": sig});
  if (response.statusCode == 200) {
    return true;
  }
  return false;
}

Future<Rates> merchantRates() async {
  var baseUrl = await Prefs.apiserverGet();
  var url = baseUrl + "rates";
  var apikey = await Prefs.apikeyGet();
  var apisecret = await Prefs.apisecretGet();
  checkApiKey(apikey, apisecret);
  var nonce = DateTime.now().toUtc().millisecondsSinceEpoch / 1000;
  var body = jsonEncode({"api_key": apikey, "nonce": nonce});
  var sig = createHmacSig(apisecret, body);
  var response = await post(url, body, extraHeaders: {"X-Signature": sig});
  if (response.statusCode == 200) {
    var jsnObj = json.decode(response.body);
    return Rates(customerRate: Decimal.parse(jsnObj["customer"]), merchantRate: Decimal.parse(jsnObj["merchant"]), settlementAddress: jsnObj["settlement_address"]);
  }
  return null;
}

Future<List<Bank>> merchantBanks() async {
  var baseUrl = await Prefs.apiserverGet();
  var url = baseUrl + "banks";
  var apikey = await Prefs.apikeyGet();
  var apisecret = await Prefs.apisecretGet();
  checkApiKey(apikey, apisecret);
  var nonce = DateTime.now().toUtc().millisecondsSinceEpoch / 1000;
  var body = jsonEncode({"api_key": apikey, "nonce": nonce});
  var sig = createHmacSig(apisecret, body);
  var response = await post(url, body, extraHeaders: {"X-Signature": sig});
  if (response.statusCode == 200) {
    var jsnObj = json.decode(response.body);
    var banks = List<Bank>();
    for (var jsnObjBank in jsnObj) {
      var bank = Bank(token: jsnObjBank["token"], accountNumber: jsnObjBank["account_number"], defaultAccount: jsnObjBank["default_account"]);
      banks.add(bank);
    }
    return banks;  
  }
  return null;
}

Future<SettlementResult> merchantSettlement(Decimal amount, String bankToken) async {
  var baseUrl = await Prefs.apiserverGet();
  var url = baseUrl + "settlement";
  var apikey = await Prefs.apikeyGet();
  var apisecret = await Prefs.apisecretGet();
  checkApiKey(apikey, apisecret);
  var nonce = DateTime.now().toUtc().millisecondsSinceEpoch / 1000;
  var d100 = Decimal.fromInt(100);
  var body = jsonEncode({"api_key": apikey, "nonce": nonce, "bank": bankToken, "amount": (amount * d100).toInt()});
  var sig = createHmacSig(apisecret, body);
  var response = await post(url, body, extraHeaders: {"X-Signature": sig});
  if (response.statusCode == 200) {
    var jsnObj = json.decode(response.body);
    return SettlementResult(
      Settlement(token: jsnObj["token"], amount: Decimal.fromInt(jsnObj["amount"]) / d100, amountReceive: Decimal.fromInt(jsnObj["amount_receive"]) / d100, bankAccount: jsnObj["bankAccount"], txid: jsnObj["txid"], status: jsnObj["status"]),
      null);
  }
  var jsnObj = json.decode(response.body);
  return SettlementResult(null, jsnObj["message"]);
}

Future<SettlementResult> merchantSettlementUpdate(String token, String txid) async {
  var baseUrl = await Prefs.apiserverGet();
  var url = baseUrl + "settlement_set_txid";
  var apikey = await Prefs.apikeyGet();
  var apisecret = await Prefs.apisecretGet();
  checkApiKey(apikey, apisecret);
  var nonce = DateTime.now().toUtc().millisecondsSinceEpoch / 1000;
  var body = jsonEncode({"api_key": apikey, "nonce": nonce, "token": token, "txid": txid});
  var sig = createHmacSig(apisecret, body);
  var response = await post(url, body, extraHeaders: {"X-Signature": sig});
  if (response.statusCode == 200) {
    var jsnObj = json.decode(response.body);
    var d100 = Decimal.fromInt(100);
    return SettlementResult( 
      Settlement(token: jsnObj["token"], amount: Decimal.fromInt(jsnObj["amount"]) / d100, amountReceive: Decimal.fromInt(jsnObj["amount_receive"]) / d100, bankAccount: jsnObj["bankAccount"], txid: jsnObj["txid"], status: jsnObj["status"]),
      null);
  }
  var jsnObj = json.decode(response.body);
  return SettlementResult(null, jsnObj["message"]);
}

typedef TxNotificationCallback = void Function(String txid, String sender, String recipient, double amount, String attachment);
Future<Socket> merchantSocket(TxNotificationCallback txNotificationCallback) async {
  var baseUrl = await Prefs.apiserverGet();
  var apikey = await Prefs.apikeyGet();
  var apisecret = await Prefs.apisecretGet();
  var nonce = DateTime.now().toUtc().millisecondsSinceEpoch / 1000;
 
  var socket = io(baseUrl, <String, dynamic>{
    'secure': true,
    'transports': ['websocket'],
  });
  socket.on('connect', (_) {
    print('ws connect');
    var sig = createHmacSig(apisecret, nonce.toString());
    var auth = {"signature": sig, "api_key": apikey, "nonce": nonce};
    socket.emit('auth', auth);
  });
  socket.on('connecting', (_) {
    print('ws connecting');
  });
  socket.on('connect_error', (err) {
    print('ws connect error ($err)');
  });
  socket.on('connect_timeout', (_) {
    print('ws connect timeout');
  });
  socket.on('info', (data) {
    print(data);
  });
  socket.on('tx', (data) {
    print(data);
    var json = jsonDecode(data);
    txNotificationCallback(json["id"], json["sender"], json["recipient"], json["amount"].toDouble(), json["attachment"]);
  });
  socket.on('disconnect', (_) {
    print('ws disconnect');
  });
 
  return socket;
}

Decimal equivalentCustomerZapForNzd(Decimal nzdReqOrProvided, Rates rates) {
  return nzdReqOrProvided * (Decimal.fromInt(1) + rates.customerRate);
}