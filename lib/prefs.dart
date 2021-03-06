import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ini/ini.dart';

import 'libzap.dart';

class Wallet {
  final String mnemonic;
  final String address;

  Wallet.mnemonic(this.mnemonic, this.address);
  Wallet.justAddress(this.address) : mnemonic = null;

  bool get isMnemonic => mnemonic != null && mnemonic.isNotEmpty;
  bool get isAddress => !isMnemonic && address != null && address.isNotEmpty;
}

class PrefHelper {
  static final _section = "main";

  PrefHelper();

  static Future<Config> fromFile() async {
    var config = Config();
    var f = File("zap.ini");
    if (await f.exists()) {
      var data = await File("zap.ini").readAsLines();
      config = Config.fromStrings(data);
    }
    if (!config.hasSection(_section))
      config.addSection(_section);
    return config;
  }

  Future<void> toFile(Config config) async {
    await File("zap.ini").writeAsString(config.toString());
  }

  Future<void> setBool(String key, bool value) async {
    if (Platform.isAndroid || Platform.isIOS) {
      final prefs = await SharedPreferences.getInstance();
      prefs.setBool(key, value);
    }
    else {
      var config = await fromFile();
      config.set(_section, key, value.toString());
      await toFile(config);
    }
  }

  Future<bool> getBool(String key, bool defaultValue) async {
    if (Platform.isAndroid || Platform.isIOS) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(key) ?? defaultValue;
    }
    else {
      var config = await fromFile();
      var value = config.get(_section, key) ?? defaultValue.toString();
      return value.toLowerCase() == 'true';
    }  
  }

  Future<void> setString(String key, String value) async {
    if (Platform.isAndroid || Platform.isIOS) {
      final prefs = await SharedPreferences.getInstance();
      prefs.setString(key, value);
    }
    else {
      var config = await fromFile();
      config.set(_section, key, value);
      await toFile(config);
    }
  }

  Future<String> getString(String key, String defaultValue) async {
    if (Platform.isAndroid || Platform.isIOS) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key) ?? defaultValue;
    }
    else {
      var config = await fromFile();
      return config.get(_section, key) ?? defaultValue;
    }  
  }
}

class Prefs {
  static Future<String> getKeyNetworkSpecific(String key) async {
    var testnet = await testnetGet();
    if (!testnet)
      key = '${key}_mainnet';
    return key;
  }

  static Future<String> getStringNetworkSpecific(String key, String defaultValue) async {
    final prefs = PrefHelper();
    return prefs.getString(await getKeyNetworkSpecific(key), defaultValue);
  }

  static Future<bool> setStringNetworkSpecific(String key, String value) async {
    final prefs = PrefHelper();
    prefs.setString(await getKeyNetworkSpecific(key), value);
    return true;
  }

  static Future<bool> testnetGet() async {
    final prefs = PrefHelper();
    return await prefs.getBool("testnet", false);
  }

  static void testnetSet(bool value) async {
    final prefs = PrefHelper();
    await prefs.setBool("testnet", value);

    // set libzap
    LibZap().testnetSet(value);
  }

  static Future<String> pinGet() async {
    final prefs = PrefHelper();
    return await prefs.getString("pin", null);
  }

  static Future<bool> pinSet(String value) async {
    final prefs = PrefHelper();
    await prefs.setString("pin", value);
    return true;
  }

  static Future<String> addressGet() async {
    return await getStringNetworkSpecific("address", null);
  }

  static Future<bool> addressSet(String value) async {
    await setStringNetworkSpecific("address", value);
    return true;
  }

  static Future<String> mnemonicGet() async {
    final prefs = PrefHelper();
    return await prefs.getString("mnemonic", null);
  }

  static Future<bool> mnemonicSet(String value) async {
    final prefs = PrefHelper();
    await prefs.setString("mnemonic", value);
    return true;
  }

  static Future<bool> mnemonicPasswordProtectedGet() async {
    var iv = await cryptoIVGet();
    return iv != null;
  }

  static Future<String> cryptoIVGet() async {
    final prefs = PrefHelper();
    return await prefs.getString("IV", null);
  }

  static Future<bool> cryptoIVSet(String value) async {
    final prefs = PrefHelper();
    await prefs.setString("IV", value);
    return true;
  }

  static Future<String> deviceNameGet() async {
    return await getStringNetworkSpecific("deviceName", null);
  }

  static Future<bool> deviceNameSet(String value) async {
    await setStringNetworkSpecific("deviceName", value);
    return true;
  }

  static Future<String> apikeyGet() async {
    return await getStringNetworkSpecific("apikey", null);
  }

  static Future<bool> apikeySet(String value) async {
    await setStringNetworkSpecific("apikey", value);
    return true;
  }

  static Future<String> apisecretGet() async {
    return await getStringNetworkSpecific("apisecret", null);
  }

  static Future<bool> apisecretSet(String value) async {
    await setStringNetworkSpecific("apisecret", value);
    return true;
  }

  static Future<String> apiserverGet() async {
    var server = await getStringNetworkSpecific("apiserver", null);
    if (server == null || server.isEmpty)
      server = "https://merchant.map.me/";
    return server;
  }

  static Future<bool> apiserverSet(String value) async {
    await setStringNetworkSpecific("apiserver", value);
    return true;
  }
}