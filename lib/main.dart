import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qrcode_reader/qrcode_reader.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter_icons/flutter_icons.dart';
import 'package:socket_io_client/socket_io_client.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import 'qrwidget.dart';
import 'send_receive.dart';
import 'reward.dart';
import 'settlement.dart';
import 'settings.dart';
import 'utils.dart';
import 'libzap.dart';
import 'prefs.dart';
import 'new_mnemonic_form.dart';
import 'transactions.dart';
import 'merchant.dart';
import 'widgets.dart';
import 'recovery_form.dart';

void main() {
  // See https://github.com/flutter/flutter/wiki/Desktop-shells#target-platform-override
  _setTargetPlatformForDesktop();  

  runApp(MyApp());
}

/// If the current platform is desktop, override the default platform to
/// a supported platform (iOS for macOS, Android for Linux and Windows).
/// Otherwise, do nothing.
void _setTargetPlatformForDesktop() {
  TargetPlatform targetPlatform;
  if (Platform.isMacOS) {
    targetPlatform = TargetPlatform.iOS;
  } else if (Platform.isLinux || Platform.isWindows) {
    targetPlatform = TargetPlatform.android;
  }
  if (targetPlatform != null) {
    debugDefaultTargetPlatformOverride = targetPlatform;
  }
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // unfocus any text fields when touching non interactive part of app
        // this should hide any keyboards
        var currentFocus = FocusScope.of(context);
        if (!currentFocus.hasPrimaryFocus && currentFocus.focusedChild != null) {
          FocusManager.instance.primaryFocus.unfocus();
        }
      },
      child: MaterialApp(
        title: 'Zap Merchant',
        theme: ThemeData(
          brightness: Brightness.light,
          primaryColor: Colors.white,
          accentColor: zapblue,
          textTheme: GoogleFonts.oxygenTextTheme(
            Theme.of(context).textTheme,
          ),
        ),
        home: ZapHomePage(title: 'Zap Merchant'),
      )
    );
  }
}

class ZapHomePage extends StatefulWidget {
  ZapHomePage({Key key, this.title}) : super(key: key);

  final String title;

  @override
  _ZapHomePageState createState() => new _ZapHomePageState();
}

enum NoWalletAction { CreateMnemonic, RecoverMnemonic, RecoverRaw, ScanMerchantApiKey }

class _ZapHomePageState extends State<ZapHomePage> with WidgetsBindingObserver {
  Socket _socket;
  
  bool _testnet = true;
  Wallet _wallet;
  Decimal _fee = Decimal.parse("0.01");
  Decimal _balance = Decimal.fromInt(-1);
  String _balanceText = "...";
  bool _updatingBalance = true;
  bool _showAlerts = true;
  List<String> _alerts = List<String>();
  Rates _merchantRates;

  _ZapHomePageState();

  @override
  void initState() {
    _init();
    // add WidgetsBindingObserver
    WidgetsBinding.instance.addObserver(this);
    super.initState();
  }

  @override
  void dispose() {
    // remove WidgetsBindingObserver
    WidgetsBinding.instance.removeObserver(this);
    // close socket
    if (_socket != null) 
      _socket.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print("App lifestyle state changed: $state");
    if (state == AppLifecycleState.resumed)
      _watchAddress();
  }

  void _txNotification(String txid, String sender, String recipient, double amount, String attachment) {
    var amountString = "${amount.toStringAsFixed(2)} ZAP";
    // convert amount to NZD
    if (_merchantRates != null) {
      var amountNZD = amount / (1.0 + _merchantRates.merchantRate.toDouble());
      amountString += " / ${amountNZD.toStringAsFixed(2)} NZD";
    }
    // decode attachment
    if (attachment != null && attachment.isNotEmpty)
        attachment = base58decodeString(attachment);
    // show user overview of new tx
    showDialog(
      context: context,
      barrierDismissible: false, // dialog is dismissible with a tap on the barrier
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("received $amountString"),
          content: Container(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: <Widget>[
                ListTile(title: Text("TXID"), subtitle: Text(txid)),
                ListTile(title: Text("sender"), subtitle: Text(sender),),
                ListTile(title: Text("amount"), subtitle: Text(amountString)),
                ListTile(title: Text(attachment != null && attachment.isNotEmpty ? "attachment" : ""), subtitle: Text(attachment != null && attachment.isNotEmpty ? attachment : "")),
              ],
            ),
          ),
          actions: <Widget>[
            RoundedButton(() => Navigator.pop(context), zapblue, Colors.white, 'ok', borderColor: zapblue),
          ],
        );
      }
    );
    // alert server to update merchant tx table
    merchantTx();
    // update balance
    _updateBalance();
  }

  void _watchAddress() async {
    // do nothing if the address, apikey or apisecret is not set
    if (_wallet == null)
      return;
    if (!await hasApiKey())
      return;
    // register to watch our address
    if (!await merchantWatch(_wallet.address))
    {
      flushbarMsg(context, 'failed to register address', category: MessageCategory.Warning);
      return;
    }
    // create socket to receive tx alerts
    if (_socket != null) 
      _socket.close();
    _socket = await merchantSocket(_txNotification);
  }

  Future<NoWalletAction> _noWalletDialog(BuildContext context) async {
    return await showDialog<NoWalletAction>(
        context: context,
        barrierDismissible: true,
        builder: (BuildContext context) {
          return SimpleDialog(
            title: const Text("You do not have recovery words or an address saved, what would you like to do?"),
            children: <Widget>[
              SimpleDialogOption(
                onPressed: () {
                  Navigator.pop(context, NoWalletAction.CreateMnemonic);
                },
                child: const Text("Create new recovery words"),
              ),
              SimpleDialogOption(
                onPressed: () {
                  Navigator.pop(context, NoWalletAction.RecoverMnemonic);
                },
                child: const Text("Recover using your recovery words"),
              ),
              SimpleDialogOption(
                onPressed: () {
                  Navigator.pop(context, NoWalletAction.RecoverRaw);
                },
                child: const Text("Recover using a raw seed string (advanced use only)"),
              ),
              SimpleDialogOption(
                onPressed: () {
                  Navigator.pop(context, NoWalletAction.ScanMerchantApiKey);
                },
                child: const Text("Scan merchant api key"),
              ),
            ],
          );
        });
  }

  Future<String> _recoverMnemonic(BuildContext context) {
    return Navigator.push<String>(context, MaterialPageRoute(builder: (context) => RecoveryForm()));
  }

  Future<String> _recoverSeed(BuildContext context) async {
    String seed = "";
    return showDialog<String>(
      context: context,
      barrierDismissible: false, // dialog is dismissible with a tap on the barrier
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Enter your raw seed string to recover your account"),
          content: Row(
            children: <Widget>[
              Expanded(
                child: Container(
                  constraints: BoxConstraints(maxWidth: 300),
                  child: TextField(
                    autofocus: true,
                    decoration: InputDecoration(labelText: "Seed",),
                    onChanged: (value) {
                      seed = value;
                    },
                  )
                )
              )
            ],
          ),
          actions: <Widget>[
            FlatButton(
              child: Text("Ok"),
              onPressed: () {
                Navigator.of(context).pop(seed);
              },
            ),
          ],
        );
      },
    );
  }

  void _noWallet() async {
    var libzap = LibZap();
    while (true) {
      String mnemonic;
      String address;
      var action = await _noWalletDialog(context);
      switch (action) {
        case NoWalletAction.CreateMnemonic:
          mnemonic = libzap.mnemonicCreate();
          // show warning for new mnemonic
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => NewMnemonicForm(mnemonic)),
          );
          break;
        case NoWalletAction.RecoverMnemonic:
          // recover mnemonic
          mnemonic = await _recoverMnemonic(context);
          if (mnemonic != null) {
            mnemonic = mnemonic.trim();
            mnemonic = mnemonic.replaceAll(RegExp(r"\s+"), " ");
            mnemonic = mnemonic.toLowerCase();
            if (!libzap.mnemonicCheck(mnemonic)) {
              mnemonic = null;
            }
          }
          if (mnemonic == null)
            await alert(context, "Recovery words not valid", "The recovery words you entered are not valid");
          break;
        case NoWalletAction.RecoverRaw:
          // recover raw seed string
          mnemonic = await _recoverSeed(context);
          break;
        case NoWalletAction.ScanMerchantApiKey:
          var value = await new QRCodeReader().scan();
          if (value != null) {
            var result = parseApiKeyUri(value);
            if (result.error == NO_ERROR) {
              if (result.walletAddress == null || result.walletAddress.isEmpty) {
                flushbarMsg(context, 'wallet address not present', category: MessageCategory.Warning);
                break;
              }
              await Prefs.addressSet(result.walletAddress);
              await Prefs.deviceNameSet(result.deviceName);
              await Prefs.apikeySet(result.apikey);
              await Prefs.apisecretSet(result.apisecret);
              flushbarMsg(context, 'API KEY set');
              address = result.walletAddress;
            }
            else
              flushbarMsg(context, 'invalid QR code', category: MessageCategory.Warning);
          }
          break;
      }
      if (mnemonic != null && mnemonic.isNotEmpty) {
        await Prefs.mnemonicSet(mnemonic);
        await alert(context, "Recovery words saved", ":)");
        // update wallet details now we have a mnemonic
        _setWalletDetails();
        break;
      }
      if (address != null && address.isNotEmpty) {
        await Prefs.addressSet(address);
        await alert(context, "Address saved", ":)");
        // update wallet details now we have an address
        _setWalletDetails();
        break;
      }
    }
  }

  Future<bool> _updateTestnet() async {
    // update testnet
    _testnet = await _setTestnet(_wallet.address, _wallet.isMnemonic);
    setState(() {
      var testnetText = 'Testnet!';
      if (_testnet && !_alerts.contains(testnetText))
        _alerts.add(testnetText);
      if (!_testnet && _alerts.contains(testnetText))
        _alerts.remove(testnetText);
    });
    return true;
  }

  Future<bool> _updateBalance() async {
    // start updating balance spinner
    setState(() {
      _updatingBalance = true;
    });
    // update state
    setState(() {
      _wallet = _wallet;
    });
    // get fee
    var feeResult = await LibZap.transactionFee();
    // get balance
    var balanceResult = await LibZap.addressBalance(_wallet.address);
    // update state
    setState(() {
      if (feeResult.success)
        _fee = Decimal.fromInt(feeResult.value) / Decimal.fromInt(100);
      if (balanceResult.success) {
        _balance = Decimal.fromInt(balanceResult.value) / Decimal.fromInt(100);
        _balanceText = _balance.toStringAsFixed(2);
      }
      else {
        _balance = Decimal.fromInt(-1);
        _balanceText = ":(";
      }
      _updatingBalance = false;
    });
    return true;
  }

  Future<bool> _setWalletDetails() async {
    _alerts.clear();
    // check apikey
    if (!await hasApiKey())
      setState(() => _alerts.add('No API KEY set'));
    // check mnemonic
    if (_wallet == null) {
      var libzap = LibZap();
      var mnemonic = await Prefs.mnemonicGet();
      if (mnemonic != null && mnemonic.isNotEmpty) {
        var mnemonicPasswordProtected = await Prefs.mnemonicPasswordProtectedGet();
        if (mnemonicPasswordProtected) {
          while (true) {
            var password = await askMnemonicPassword(context);
            if (password == null || password.isEmpty) {
              continue;
            }
            var iv = await Prefs.cryptoIVGet();
            var decryptedMnemonic = decryptMnemonic(mnemonic, iv, password);
            if (decryptedMnemonic == null) {
              await alert(context, "Could not decrypt recovery words", "the password entered is probably wrong");
              continue;
            }
            if (!libzap.mnemonicCheck(decryptedMnemonic)) {
              var yes = await askYesNo(context, 'The recovery words are not valid, is this ok?');
              if (!yes)
                continue;
            }
            mnemonic = decryptedMnemonic;
            break;
          }
        }
        var address = libzap.seedAddress(mnemonic);
        _wallet = Wallet.mnemonic(mnemonic, address);
      } else {
        var address = await Prefs.addressGet();
        if (address != null && address.isNotEmpty) {
          _wallet = Wallet.justAddress(address);
        } else {
          return false;
        }
      }
    } else if (_wallet.isMnemonic) {
      // reinitialize wallet address (we might have toggled testnet)
      var address = LibZap().seedAddress(_wallet.mnemonic);
      _wallet = Wallet.mnemonic(_wallet.mnemonic, address);
    }
    // update testnet and balance
    _updateTestnet();
    _updateBalance();
    // watch wallet address
    _watchAddress();
    // update merchant rates
    if (await hasApiKey())
      merchantRates().then((value) => _merchantRates = value);
    return true;
  }

  void _showQrCode() {
    showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return Align(alignment: Alignment.center, child: Card(
          child: InkWell(child: Container(width: 300, height: 300,
            child: QrWidget(_wallet.address, size: 300)),
            onTap: () => Navigator.pop(context))
        ));
      },
    );
  }

  void _copyAddress() {
    Clipboard.setData(ClipboardData(text: _wallet.address)).then((value) {
      flushbarMsg(context, 'copied address to clipboard');
    });
  }

  void _scanQrCode() async {
    var value = await new QRCodeReader().scan();
    if (value != null) {
      var result = parseRecipientOrWavesUri(_testnet, value);
      if (result != null) {
        var sentFunds = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
              builder: (context) => SendScreen(_testnet, _wallet.mnemonic, _fee, value, _balance)),
        );
        if (sentFunds)
          _updateBalance();
      }
      else {
        var result = parseClaimCodeUri(value);
        if (result.error == NO_ERROR) {
          if (await merchantClaim(result.code, _wallet.address))
            flushbarMsg(context, 'claim succeded');
          else 
            flushbarMsg(context, 'claim failed', category: MessageCategory.Warning);
        }
        else
          flushbarMsg(context, 'invalid QR code', category: MessageCategory.Warning);
      }
    }
  }

  void _send() async {
    var sentFunds = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (context) => SendScreen(_testnet, _wallet.mnemonic, _fee, '', _balance)),
    );
    if (sentFunds)
      _updateBalance();
  }

  void _receive() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ReceiveScreen(_testnet, _wallet.address)),
    );
  }

  void _transactions() async {
    var deviceName = await Prefs.deviceNameGet();
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => TransactionsScreen(_wallet.address, _testnet, _haveSeed() ? null : deviceName, _merchantRates)),
    );
  }

  void _showSettings() async {
    var _pinExists = await pinExists();
    if (!await pinCheck(context)) {
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => SettingsScreen(_pinExists, _wallet.mnemonic)),
    );
    _setWalletDetails();
  }

  void _zapReward() async {
    var sentFunds = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (context) => RewardScreen(_testnet, _wallet.mnemonic, _fee, _balance)),
    );
    if (sentFunds)
      _updateBalance();
  }

  void _settlement() async {
    var sentFunds = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (context) => SettlementScreen(_testnet, _wallet.mnemonic, _fee, _balance)),
    );
    if (sentFunds)
      _updateBalance();
  }

  bool _haveSeed() {
    return _wallet != null && _wallet.isMnemonic;
  }

  Future<bool> _setTestnet(String address, bool haveMnemonic) async {
    var testnet = await Prefs.testnetGet();
    var libzap = LibZap();
    libzap.testnetSet(testnet);
    if (!haveMnemonic) {
      if (!libzap.addressCheck(address)) {
        testnet = !testnet;
        libzap.testnetSet(testnet);
        await Prefs.testnetSet(testnet);
      }
    }
    return testnet;
  }

  void _toggleAlerts() {
    setState(() => _showAlerts = !_showAlerts);
  }

  void _init() async  {
    // set libzap to initial testnet value so we can devrive address from mnemonic
    var testnet = await Prefs.testnetGet();
    LibZap().testnetSet(testnet);
    // init wallet
    var hasWallet = await _setWalletDetails();
    if (!hasWallet) {
      _noWallet();
      _setWalletDetails();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: Visibility(
          child: IconButton(onPressed: _toggleAlerts, icon: Icon(Icons.warning, color: _showAlerts ? Colors.grey : zapwarning)),
          maintainSize: true, 
          maintainAnimation: true,
          maintainState: true,
          visible: _alerts.length > 0, 
        ),
        title: Center(child: Image.asset('assets/icon.png', height: 30)),
        actions: <Widget>[
          IconButton(icon: Icon(Icons.settings, color: zapblue), onPressed: _showSettings),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _updateBalance,
        child: ListView(
          children: <Widget>[
            Visibility(
              visible: _showAlerts && _alerts.length > 0,
              child: AlertDrawer(_toggleAlerts, _alerts)
            ),
            Visibility(
              visible: _haveSeed(),
              child: Column(children: <Widget>[
                Container(
                  padding: const EdgeInsets.only(top: 28.0),
                  child: Text('my balance:',  style: TextStyle(color: zapblackmed, fontWeight: FontWeight.w700), textAlign: TextAlign.center,),
                ),
                Container(
                  height: 100,
                  width: MediaQuery.of(context).size.width,
                  child: Card(
                    child: Align(alignment: Alignment.center, 
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Visibility(
                            visible: _updatingBalance,
                            child: SizedBox(child: CircularProgressIndicator(), height: 28.0, width: 28.0,)
                          ),
                          Visibility(
                            visible: !_updatingBalance,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                Text(_balanceText, style: TextStyle(color: zapblue, fontSize: 28)),
                                SizedBox.fromSize(size: Size(4, 1)),
                                SvgPicture.asset('assets/icon-bolt.svg', height: 20)
                              ],
                            )
                          )
                        ]
                      )
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10.0),
                    ),
                    margin: EdgeInsets.all(10),
                  ),
                ),
              ],)
            ),
            Container(
              padding: const EdgeInsets.only(top: 28.0),
              child: Text('wallet address:', style: TextStyle(color: zapblackmed, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
            ),
            Container(
              padding: const EdgeInsets.only(top: 18.0),
              child: Text(_wallet != null ? _wallet.address : '...', style: TextStyle(color: zapblacklight), textAlign: TextAlign.center),
            ),
            Divider(),
            Container(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  RoundedButton(_showQrCode, zapblue, Colors.white, 'view QR code', icon: MaterialCommunityIcons.qrcode_scan, minWidth: MediaQuery.of(context).size.width / 2 - 20),
                  RoundedButton(_copyAddress, Colors.white, zapblue, 'copy wallet address', minWidth: MediaQuery.of(context).size.width / 2 - 20),
                ]
              )
            ),
            Container(
              //height: 300, ???
              margin: const EdgeInsets.only(top: 40),
              padding: const EdgeInsets.only(top: 20),
              color: Colors.white,
              child: Column(
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: <Widget>[
                      _haveSeed() ? SquareButton(_send, MaterialCommunityIcons.chevron_double_up, zapyellow, 'SEND ZAP') : null,
                      _haveSeed() ? SquareButton(_scanQrCode, MaterialCommunityIcons.qrcode_scan, zapblue, 'SCAN QR CODE') : null,
                      SquareButton(_receive, MaterialCommunityIcons.chevron_double_down, zapgreen, 'RECEIVE ZAP'),
                    ].where((child) => child != null).toList(),
                  ),
                  SizedBox.fromSize(size: Size(1, 10)),
                  ListButton(_transactions, 'transactions', !_haveSeed()),
                  //ListButton(_zapRewards, 'zap rewards', false),
                  Visibility(
                    visible: _haveSeed(),
                    child: 
                      ListButton(_settlement, 'make settlement', _haveSeed()),
                 ),
                ],
              )
            ),      
          ],
        ),
      ),
    );
  }
}
