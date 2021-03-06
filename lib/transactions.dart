import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:decimal/decimal.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';

import 'libzap.dart';
import 'utils.dart';
import 'widgets.dart';
import 'merchant.dart';

class TransactionsScreen extends StatefulWidget {
  final String _address;
  final bool _testnet;
  final String _deviceName;
  final Rates _merchantRates;

  TransactionsScreen(this._address, this._testnet, this._deviceName, this._merchantRates) : super();

  @override
  _TransactionsState createState() => new _TransactionsState();
}

enum LoadDirection {
  Next, Previous, Initial
}

class Choice {
  const Choice({this.title, this.icon});

  final String title;
  final IconData icon;
}

const List<Choice> choices = const <Choice>[
  const Choice(title: "Export JSON", icon: Icons.save),
];

class DownloadResult {
  final int downloadCount;
  final int validCount;
  DownloadResult(this.downloadCount, this.validCount);
}

class _TransactionsState extends State<TransactionsScreen> {
  bool _loading = true;
  var _txsAll = List<Tx>();
  var _txsFiltered = List<Tx>();
  var _offset = 0;
  var _downloadCount = 100;
  var _displayCount = 10;
  String _after;
  var _more = false;
  var _less = false;
  var _foundEnd = false;

  @override
  void initState() {
    _loadTxs(LoadDirection.Initial);
    super.initState();
  }

  Future<DownloadResult> _downloadMoreTxs(int count) async {
    var txs = await LibZap.addressTransactions(widget._address, count, _after);
    var txsFiltered = List<Tx>();
    if (txs != null) {
      for (var tx in txs) {
        // check asset id
        var zapAssetId = widget._testnet ? LibZap.TESTNET_ASSET_ID : LibZap.MAINNET_ASSET_ID;
        if (tx.assetId != zapAssetId)
          continue;
        // decode attachment
        if (tx.attachment != null && tx.attachment.isNotEmpty)
          tx.attachment = base58decodeString(tx.attachment);
        // check device name
        var deviceName = '';
        try {
          deviceName = json.decode(tx.attachment)['device_name'];
        } catch (_) {}
        if (widget._deviceName != null && widget._deviceName.isNotEmpty && widget._deviceName != deviceName)
          continue;
        txsFiltered.add(tx);
      }
      _txsAll += txs;
      _txsFiltered += txsFiltered;
      if (_txsAll.length > 0)
        _after = _txsAll[_txsAll.length - 1].id;
      if (txs.length < count)
        _foundEnd = true;
    }
    else
      return null;
    return DownloadResult(txs.length, txsFiltered.length);
  }

  void _loadTxs(LoadDirection dir) async {
    var newOffset = _offset;
    if (dir == LoadDirection.Next) {
      newOffset += _displayCount;
      if (newOffset > _txsFiltered.length)
        newOffset = _txsFiltered.length;
    }
    else if (dir == LoadDirection.Previous) {
      newOffset -= _displayCount;
      if (newOffset < 0)
        newOffset = 0;
    }
    if (newOffset == _txsFiltered.length) {
      // set loading
      setState(() {
        _loading = true;
      });
      // load new txs
      var count = 0;
      var remaining = _displayCount;
      var failed = false;
      while (true) {
        var res = await _downloadMoreTxs(_downloadCount);
        if (res == null) {
          flushbarMsg(context, 'failed to load transactions', category: MessageCategory.Warning);
          failed = true;
          break;
        }
        count += res.validCount;
        if (count >= _displayCount || res.downloadCount < remaining)
          break;
        remaining = _displayCount - count;
      }
      setState(() {
        if (!failed) {
          _more = count >= _displayCount;
          _less = newOffset > 0;
          _offset = newOffset;
        }
        _loading = false;
      });
    }
    else {
      setState(() {
        _more = !_foundEnd || newOffset < _txsFiltered.length - _displayCount;
        _less = newOffset > 0;
        _offset = newOffset;
      });
    }
  }

  Widget _buildTxList(BuildContext context, int index) {
    var offsetIndex = _offset + index;
    if (offsetIndex >= _offset + _displayCount || offsetIndex >= _txsFiltered.length)
      return null;
    var tx = _txsFiltered[offsetIndex];
    var outgoing = tx.sender == widget._address;
    var amount = Decimal.fromInt(tx.amount) / Decimal.fromInt(100);
    var amountText = "${amount.toStringAsFixed(2)} ZAP";
    if (widget._merchantRates != null)
      amountText = "$amountText / ${toNZDAmount(amount, widget._merchantRates)}";
    amountText = outgoing ? '- $amountText' : '+ $amountText';
    var fee = Decimal.fromInt(tx.fee) / Decimal.fromInt(100);
    var feeText = fee.toStringAsFixed(2);
    var color = outgoing ? zapyellow : zapgreen;
    var date = new DateTime.fromMillisecondsSinceEpoch(tx.timestamp);
    var dateStrLong = DateFormat('yyyy-MM-dd HH:mm').format(date);
    var link = widget._testnet ? 'https://wavesexplorer.com/testnet/tx/${tx.id}' : 'https://wavesexplorer.com/tx/${tx.id}';
    return ListTx(() {
      Navigator.of(context).push(
        // We will now use PageRouteBuilder
        PageRouteBuilder(
          opaque: false,
          pageBuilder: (BuildContext context, __, ___) {
            return new Scaffold(
              appBar: AppBar(
                leading: backButton(context, color: zapblue),
                title: Text('transaction', style: TextStyle(color: zapblue)),
              ),
              body: Container(
                color: Colors.white,
                child: Column(
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.only(top: 5.0),
                      child: ListTile(title: Text('transaction ID'),
                          subtitle: InkWell(
                            child: Text(tx.id, style: new TextStyle(color: zapblue, decoration: TextDecoration.underline))),
                            onTap: () => launch(link),
                          ),
                    ),
                    ListTile(title: Text('date'), subtitle: Text(dateStrLong)),
                    ListTile(title: Text('sender'), subtitle: Text(tx.sender)),
                    ListTile(title: Text('recipient'), subtitle: Text(tx.recipient)),
                    ListTile(title: Text('amount'), subtitle: Text(amountText, style: TextStyle(color: color),)),
                    ListTile(title: Text('fee'), subtitle: Text('$feeText ZAP',)),
                    Visibility(
                      visible: tx.attachment != null && tx.attachment.isNotEmpty,
                      child:
                        ListTile(title: Text("attachment"), subtitle: Text(tx.attachment)),
                    ),
                    Container(
                      padding: const EdgeInsets.only(top: 5.0),
                      child: RoundedButton(() => Navigator.pop(context), zapblue, Colors.white, 'close', borderColor: zapblue)
                    ),
                  ],
                ),
              )
            );
          }
        )
      );
    }, date, tx.id, amount, widget._merchantRates, outgoing);
  }

  void _select(Choice choice) async {
    switch (choice.title) {
      case "Export JSON":
        setState(() {
          _loading = true;
        });
        while (true) {
          var txs = await _downloadMoreTxs(_downloadCount);
          if (txs == null) {
            flushbarMsg(context, 'failed to load transactions', category: MessageCategory.Warning);
            setState(() {
              _loading = false;
            });
            return;
          }
          else if (_foundEnd) {
            var json = jsonEncode(_txsFiltered);
            var filename = "zap_txs.json";
            if (Platform.isAndroid || Platform.isIOS) {
              var dir = await getExternalStorageDirectory();
              filename = dir.path + "/" + filename;
            }
            await File(filename).writeAsString(json);
            alert(context, "Wrote JSON", filename);
            setState(() {
              _loading = false;
            });
            break;
          }
          flushbarMsg(context, 'loaded ${_txsFiltered.length} transactions');
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: backButton(context, color: zapblue),
        title: Text("transactions", style: TextStyle(color: zapblue)),
        actions: <Widget>[
          PopupMenuButton<Choice>(
            icon: Icon(Icons.more_vert, color: zapblue),
            onSelected: _select,
            enabled: !_loading,
            itemBuilder: (BuildContext context) {
              return choices.map((Choice choice) {
                return PopupMenuItem<Choice>(
                  value: choice,
                  child: Text(choice.title),
                );
              }).toList();
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: _loading ? MainAxisAlignment.center : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Visibility(
                visible: !_loading && _txsFiltered.length == 0,
                child: Text("Nothing here..")),
            Visibility(
              visible: !_loading,
              child: Expanded(
                child: new ListView.builder(
                  itemCount: _txsFiltered.length,
                  itemBuilder: (BuildContext context, int index) => _buildTxList(context, index),
                ))),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Visibility(
                    visible: !_loading && _less,
                    child: Container(
                        padding: const EdgeInsets.all(5),
                        child: RoundedButton(() => _loadTxs(LoadDirection.Previous), zapblue, Colors.white, 'prev', icon: Icons.navigate_before, borderColor: zapblue)
                    )),
                Visibility(
                    visible: !_loading && _more,
                    child: Container(
                        padding: const EdgeInsets.all(5),
                        child: RoundedButton(() => _loadTxs(LoadDirection.Next), zapblue, Colors.white, 'next', icon: Icons.navigate_next, borderColor: zapblue)
                    )),

              ],
            ),
            Visibility(
                visible: _loading,
                child: CircularProgressIndicator(),
            ),
          ],
        ),
      )
    );
  }
}