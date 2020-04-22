import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:polka_wallet/common/components/currencyWithIcon.dart';
import 'package:polka_wallet/common/components/roundedButton.dart';
import 'package:polka_wallet/common/components/roundedCard.dart';
import 'package:polka_wallet/common/regInputFormatter.dart';
import 'package:polka_wallet/page-acala/earn/earnPage.dart';
import 'package:polka_wallet/page/account/txConfirmPage.dart';
import 'package:polka_wallet/service/substrateApi/api.dart';
import 'package:polka_wallet/store/app.dart';
import 'package:polka_wallet/utils/format.dart';
import 'package:polka_wallet/utils/i18n/index.dart';

class AddLiquidityPage extends StatefulWidget {
  AddLiquidityPage(this.store);

  static const String route = '/acala/earn/deposit';
  static const String actionDeposit = 'deposit';
  static const String actionWithdraw = 'withdraw';

  final AppStore store;

  @override
  _AddLiquidityPageState createState() => _AddLiquidityPageState(store);
}

class _AddLiquidityPageState extends State<AddLiquidityPage> {
  _AddLiquidityPageState(this.store);

  final AppStore store;

  final GlobalKey<RefreshIndicatorState> _refreshKey =
      new GlobalKey<RefreshIndicatorState>();

  final _formKey = GlobalKey<FormState>();
  final TextEditingController _amountPayCtrl = new TextEditingController();
  final TextEditingController _amountReceiveCtrl = new TextEditingController();

  double _slippage = 0.005;

  Future<void> _refreshData() async {
    AddLiquidityPageParams params = ModalRoute.of(context).settings.arguments;
    String pubKey = store.account.currentAccount.pubKey;
    webApi.acala.fetchTokens(pubKey);
    webApi.acala.fetchDexLiquidityPoolSwapRatios();
    webApi.acala.fetchDexLiquidityPool();
    webApi.acala.fetchDexLiquidityPoolShare(params.token);
  }

  Future<void> _onSupplyAmountChange(String v, double swapRatio) async {
    String supply = v.trim();
    if (supply.isEmpty) {
      return;
    }
    setState(() {
      _amountReceiveCtrl.text = (double.parse(supply) * swapRatio).toString();
    });
    _formKey.currentState.validate();
  }

  Future<void> _onTargetAmountChange(String v, double swapRatio) async {
    String target = v.trim();
    if (target.isEmpty) {
      return;
    }
    setState(() {
      _amountPayCtrl.text = (double.parse(target) / swapRatio).toString();
    });
    _formKey.currentState.validate();
  }

  void _onSubmit() {
    if (_formKey.currentState.validate()) {
      int decimals = store.settings.networkState.tokenDecimals;
      List<String> swapPair = store.acala.currentSwapPair;
      String pay = _amountPayCtrl.text.trim();
      String receive = _amountReceiveCtrl.text.trim();
      var args = {
        "title": I18n.of(context).acala['dex.title'],
        "txInfo": {
          "module": 'dex',
          "call": 'swapCurrency',
        },
        "detail": jsonEncode({
          "currencyPay": swapPair[0],
          "amountPay": pay,
          "currencyReceive": swapPair[1],
          "amountReceive": receive,
        }),
        "params": [
          // params.supply
          swapPair[0],
          Fmt.tokenInt(pay, decimals: decimals).toString(),
          // params.target
          swapPair[1],
          Fmt.tokenInt(receive, decimals: decimals).toString(),
        ],
        "onFinish": (BuildContext txPageContext, Map res) {
//          print(res);
          store.acala.setSwapTxs([res]);
          Navigator.popUntil(
              txPageContext, ModalRoute.withName(EarnPage.route));
          _refreshKey.currentState.show();
        }
      };
      Navigator.of(context).pushNamed(TxConfirmPage.route, arguments: args);
    }
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshData();
    });
  }

  @override
  void dispose() {
    _amountPayCtrl.dispose();
    _amountReceiveCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(_) {
    return Observer(
      builder: (BuildContext context) {
        final Map dic = I18n.of(context).acala;
        final Map dicAssets = I18n.of(context).assets;
        int decimals = store.settings.networkState.tokenDecimals;
        AddLiquidityPageParams params =
            ModalRoute.of(context).settings.arguments;

        final double inputWidth = MediaQuery.of(context).size.width / 3;

        double shareTotal = Fmt.balanceDouble(
            (store.acala.swapPoolSharesTotal[params.token] ?? BigInt.zero)
                .toString());
        double share = Fmt.balanceDouble(
            (store.acala.swapPoolShares[params.token] ?? BigInt.zero)
                .toString());
        double userShare = share / shareTotal;

        List pool = store.acala.swapPool[params.token];
        double poolToken = Fmt.balanceDouble(
            pool != null ? pool[0].toString() : '',
            decimals: decimals);
        double poolStableCoin = Fmt.balanceDouble(
            pool != null ? pool[1].toString() : '',
            decimals: decimals);

        double balanceToken = 0;
        double balanceBaseCoin = 0;
        double userShareNew = userShare;
        String amountInput = _amountPayCtrl.text.trim();
        double shareInput =
            double.parse(amountInput.isEmpty ? '0' : amountInput) /
                poolToken *
                shareTotal;

        if (params.actionType == AddLiquidityPage.actionDeposit) {
          balanceToken = Fmt.balanceDouble(store.assets.balances[params.token],
                  decimals: decimals) ??
              BigInt.zero;
          balanceBaseCoin = Fmt.balanceDouble(
                  store.assets.balances[store.acala.acalaBaseCoin],
                  decimals: decimals) ??
              BigInt.zero;
          userShareNew = (share + shareInput) / (shareTotal + shareInput);
        } else if (params.actionType == AddLiquidityPage.actionWithdraw) {
          balanceToken = poolToken * userShare;
          balanceBaseCoin = poolStableCoin * userShare;
          userShareNew = (share - shareInput) / (shareTotal - shareInput);
        }
        print(userShareNew);

        double swapRatio =
            double.parse(store.acala.swapPoolRatios[params.token].toString());

        return Scaffold(
          appBar: AppBar(
              title: Text(dic['earn.${params.actionType}']), centerTitle: true),
          body: SafeArea(
            child: ListView(
              padding: EdgeInsets.all(16),
              children: <Widget>[
                RoundedCard(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          Container(
                            width: inputWidth,
                            child: CurrencyWithIcon(
                              params.token,
                              textWidth: 48,
                              textStyle: Theme.of(context).textTheme.display4,
                            ),
                          ),
                          Expanded(
                            child: Icon(
                              Icons.add,
                            ),
                          ),
                          Container(
                            width: inputWidth,
                            child: CurrencyWithIcon(
                              store.acala.acalaBaseCoin,
                              textWidth: 48,
                              textStyle: Theme.of(context).textTheme.display4,
                            ),
                          ),
                        ],
                      ),
                      Form(
                        key: _formKey,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Container(
                              width: inputWidth,
                              child: TextFormField(
                                decoration: InputDecoration(
                                  hintText: dic['dex.pay'],
                                  labelText: dic['dex.pay'],
                                  suffix: GestureDetector(
                                    child: Icon(
                                      CupertinoIcons.clear_thick_circled,
                                      color: Theme.of(context).disabledColor,
                                      size: 18,
                                    ),
                                    onTap: () {
                                      WidgetsBinding.instance
                                          .addPostFrameCallback(
                                              (_) => _amountPayCtrl.clear());
                                    },
                                  ),
                                ),
                                inputFormatters: [
                                  RegExInputFormatter.withRegex(
                                      '^[0-9]{0,6}(\\.[0-9]{0,$decimals})?\$')
                                ],
                                controller: _amountPayCtrl,
                                keyboardType: TextInputType.numberWithOptions(
                                    decimal: true),
                                validator: (v) {
                                  if (v.isEmpty) {
                                    return dicAssets['amount.error'];
                                  }
                                  if (double.parse(v.trim()) > balanceToken) {
                                    return dicAssets['amount.low'];
                                  }
                                  return null;
                                },
                                onChanged: (v) =>
                                    _onSupplyAmountChange(v, swapRatio),
                              ),
                            ),
                            Container(
                              width: inputWidth,
                              child: TextFormField(
                                decoration: InputDecoration(
                                  hintText: dic['dex.receive'],
                                  labelText: dic['dex.receive'],
                                  suffix: GestureDetector(
                                    child: Icon(
                                      CupertinoIcons.clear_thick_circled,
                                      color: Theme.of(context).disabledColor,
                                      size: 18,
                                    ),
                                    onTap: () {
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) =>
                                              _amountReceiveCtrl.clear());
                                    },
                                  ),
                                ),
                                inputFormatters: [
                                  RegExInputFormatter.withRegex(
                                      '^[0-9]{0,6}(\\.[0-9]{0,$decimals})?\$')
                                ],
                                controller: _amountReceiveCtrl,
                                keyboardType: TextInputType.numberWithOptions(
                                    decimal: true),
                                validator: (v) {
                                  if (v.isEmpty) {
                                    return dicAssets['amount.error'];
                                  }
                                  if (double.parse(v.trim()) >
                                      balanceBaseCoin) {
                                    return dicAssets['amount.low'];
                                  }
                                  return null;
                                },
                                onChanged: (v) =>
                                    _onTargetAmountChange(v, swapRatio),
                              ),
                            )
                          ],
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          Container(
                            width: inputWidth,
                            child: Text(
                              '${dicAssets['balance']}: $balanceToken',
                              style: TextStyle(
                                fontSize: 14,
                                color: Theme.of(context).unselectedWidgetColor,
                              ),
                            ),
                          ),
                          Container(
                            width: inputWidth,
                            child: Text(
                              '${dicAssets['balance']}: $balanceBaseCoin',
                              style: TextStyle(
                                fontSize: 14,
                                color: Theme.of(context).unselectedWidgetColor,
                              ),
                            ),
                          )
                        ],
                      ),
                      Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          Text(
                            dic['dex.rate'],
                            style: TextStyle(
                                color: Theme.of(context).unselectedWidgetColor),
                          ),
                          Text(
                              '1 ${params.token} = ${store.acala.swapPoolRatios[params.token]} ${store.acala.acalaBaseCoin}'),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          Text(
                            dic['earn.pool'],
                            style: TextStyle(
                                color: Theme.of(context).unselectedWidgetColor),
                          ),
                          Text(
                              '$poolToken ${params.token} + $poolStableCoin ${store.acala.acalaBaseCoin}'),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          Text(
                            dic['earn.share'],
                            style: TextStyle(
                                color: Theme.of(context).unselectedWidgetColor),
                          ),
                          Text(Fmt.ratio(userShareNew)),
                        ],
                      )
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: RoundedButton(
                    text: dic['earn.${params.actionType}'],
                    onPressed: _onSubmit,
                  ),
                )
              ],
            ),
          ),
        );
      },
    );
  }
}

class AddLiquidityPageParams {
  AddLiquidityPageParams(this.actionType, this.token);
  final String actionType;
  final String token;
}