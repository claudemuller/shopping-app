import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shopping/item.dart';

const _apiAddr = 'http://192.168.1.3:8090';
const _modelName = 'shoppingList';

class ShoppingListPage extends StatefulWidget {
  const ShoppingListPage({super.key, required this.title});

  final String title;

  @override
  State<ShoppingListPage> createState() => _ShoppingListPageState();
}

class _ShoppingListPageState extends State<ShoppingListPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _itemController = TextEditingController();
  final ScrollController _scrollbarCcontroller = ScrollController();

  PocketBase _pb = PocketBase(_apiAddr);
  RecordAuth? _userData;
  late StreamSubscription<ConnectivityResult>? _connectivitySubscription;
  bool _connectedToAPI = false;
  bool _isAPIReachable = false;
  bool _isNetworkReachable = false;

  final List<Item> _list = [];

  @override
  void initState() {
    super.initState();

    _checkConnection();
    _initList();
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    super.dispose();
  }

  void _simulateOffline() {
    setState(() {
      _connectedToAPI = false;
      _isNetworkReachable = false;
      _isAPIReachable = false;
    });
    _startConnectionListener();
  }

  Future<void> _checkConnection() async {
    _isNetworkReachable = await _checkNetworkConnection();
    _isAPIReachable = await _checkAPIConnection(_apiAddr);
  }

  void _startConnectionListener() {
    setState(() {
      _connectedToAPI = false;
      _isNetworkReachable = false;
      _isAPIReachable = false;
    });

    if (_connectivitySubscription != null) {
      return;
    }

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      ConnectivityResult result,
    ) {
      debugPrint('Network change detected');

      if (result != ConnectivityResult.none) {
        _pb = PocketBase(_apiAddr);

        debugPrint('Network reconnected');

        setState(() {
          _connectedToAPI = true;
          _isNetworkReachable = true;
          _isAPIReachable = true;
        });

        _connectivitySubscription?.cancel();
        _connectivitySubscription = null;

        _initList();
      }
    });
  }

  void _initList() async {
    // Login/connect to API
    try {
      _userData = await _pb
          .collection('_superusers')
          .authWithPassword('test@test.com', 'testtesttest');
      _connectedToAPI = true;
    } on SocketException catch (e) {
      debugPrint("Network error: $e");
      _startConnectionListener();
    } catch (e) {
      debugPrint("Error connecting to API: $e");
    }

    await _syncLists();
  }

  Future<void> _syncLists() async {
    List<RecordModel> remoteList = [];

    try {
      remoteList = await _pb
          .collection(_modelName)
          .getFullList(sort: 'created');
    } on SocketException catch (e) {
      debugPrint("Network error: $e");
      _startConnectionListener();
    } catch (e) {
      debugPrint("Error connecting to API: $e");
      _connectedToAPI = false;
    }

    // Merge
    _list.clear();

    for (final RecordModel item in remoteList) {
      String lastSyncedAtStr = item.getStringValue("last_synced_at");

      _list.add(
        Item(
          id: item.id,
          name: item.getStringValue("name"),
          lastSyncedAt: lastSyncedAtStr.isNotEmpty
              ? DateTime.parse(lastSyncedAtStr)
              : null,
        ),
      );
    }

    List<Item> localList = await _localGetList();
    for (final Item item in localList) {
      if (_list.any((i) => i.name.toLowerCase() == item.name.toLowerCase())) {
        continue;
      }

      if (item.lastSyncedAt == null) {
        debugPrint("${item.name} ${item.id} ${item.lastSyncedAt}");

        try {
          final Item newItem = Item(
            name: item.name,
            lastSyncedAt: DateTime.now(),
          );
          await _pb.collection(_modelName).create(body: newItem.toJson());
        } on SocketException catch (e) {
          debugPrint("Network error: $e");
          _startConnectionListener();
        } catch (e) {
          debugPrint("Error creating: $e");
        }
      }

      _list.add(item);
    }

    setState(() {}); // trigger rebuild with loaded list
  }

  void _saveItem() {
    if (_formKey.currentState!.validate()) {
      final Item newItem = Item(name: _itemController.text);

      setState(() {
        _list.add(newItem);
      });

      _localSaveList(_list);
      _remoteSaveItem(newItem);

      _itemController.clear();
    }
  }

  void _removeItem(Item item) {
    setState(() {
      _list.remove(item);
    });

    _localSaveList(_list);
    if (item.id != "") {
      _remoteDeleteItem(item.id ?? "");
    }

    _itemController.text = item.name;
  }

  // -----------------------------------------------------------------------------------------------
  // Local methods

  Future<List<Item>> _localGetList() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? jsonList = prefs.getStringList(_modelName);

    if (jsonList == null) return [];

    return jsonList
        .map((jsonStr) => Item.fromJson(jsonDecode(jsonStr)))
        .toList();
  }

  Future<void> _localSaveList(List<Item> list) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> jsonList = list
        .map((item) => jsonEncode(item.toJson()))
        .toList();
    await prefs.setStringList(_modelName, jsonList);
  }

  Future<void> _localClearStorage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_modelName);
    _syncLists();
  }

  // -----------------------------------------------------------------------------------------------
  // Remote methods

  Future<void> _remoteSaveItem(Item item) async {
    try {
      final Item newItem = Item(name: item.name, lastSyncedAt: DateTime.now());
      await _pb.collection(_modelName).create(body: newItem.toJson());
      item.lastSyncedAt = newItem.lastSyncedAt;
    } on SocketException catch (e) {
      debugPrint("Network error: $e");
      _startConnectionListener();
    } catch (e) {
      debugPrint("Remote create failed: $e");
    }

    await _syncLists();
  }

  Future<void> _remoteDeleteItem(String key) async {
    try {
      await _pb.collection(_modelName).delete(key);
    } on SocketException catch (e) {
      debugPrint("Network error: $e");
      _startConnectionListener();
    } catch (e) {
      debugPrint("Remote delete failed: $e");
    }

    await _syncLists();
  }

  // -----------------------------------------------------------------------------------------------
  // Build widgets

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.inversePrimary,
        title: Text(widget.title),
      ),

      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Form(
                key: _formKey,
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: TextFormField(
                        controller: _itemController,
                        decoration: const InputDecoration(
                          labelText: 'Enter an item to buy',
                          border: OutlineInputBorder(),
                        ),
                        validator: (String? value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter some text';
                          }
                          return null;
                        },
                        onFieldSubmitted: (item) {
                          _saveItem();
                        },
                      ),
                    ),

                    const SizedBox(width: 8),

                    FloatingActionButton.small(
                      child: const Icon(Icons.add),
                      onPressed: _saveItem,
                    ),
                  ],
                ),
              ),

              Expanded(
                child: Scrollbar(
                  thumbVisibility: true,
                  controller: _scrollbarCcontroller,
                  child: ListView.builder(
                    itemCount: _list.length,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    itemBuilder: (BuildContext context, int idx) {
                      return Dismissible(
                        key: ValueKey<Item>(_list[idx]),
                        direction: DismissDirection.horizontal,
                        background: Container(
                          color: Colors.green,
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: const [
                              Icon(Icons.check, color: Colors.white),
                              SizedBox(width: 8),
                              Text(
                                'Mark as Done',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        secondaryBackground: Container(
                          color: Colors.red,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: const [
                              Text(
                                'Delete',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(width: 8),
                              Icon(Icons.delete, color: Colors.white),
                            ],
                          ),
                        ),
                        onDismissed: (DismissDirection direction) {
                          if (direction == DismissDirection.startToEnd) {
                            setState(() {
                              _list.removeAt(idx);
                            });
                          }
                          if (direction == DismissDirection.endToStart) {
                            _removeItem(_list[idx]);
                          }

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('${_list[idx]} dismissed')),
                          );
                        },
                        child: ListTile(
                          title: Text('${_list[idx].name} [${_list[idx].id}]'),
                        ),
                      );
                    },
                  ),
                ),
              ),

              Row(
                children: [
                  _isNetworkReachable
                      ? Icon(Icons.wifi)
                      : Icon(Icons.wifi, color: Colors.grey.shade800),

                  SizedBox(width: 10),

                  _isAPIReachable
                      ? Icon(Icons.api)
                      : Icon(Icons.api, color: Colors.grey.shade800),

                  Expanded(child: SizedBox(width: 10)),

                  // FloatingActionButton.small(
                  //   child: const Icon(Icons.network_wifi),
                  //   onPressed: _simulateOffline,
                  // ),
                  FloatingActionButton.small(
                    child: const Icon(Icons.clear),
                    onPressed: _localClearStorage,
                  ),

                  SizedBox(width: 10),

                  FloatingActionButton.small(
                    child: const Icon(Icons.sync),
                    onPressed: _syncLists,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<bool> _checkNetworkConnection() async {
  return await Connectivity().checkConnectivity() != ConnectivityResult.none;
}

Future<bool> _checkAPIConnection(String baseUrl) async {
  try {
    final response = await http
        .get(Uri.parse('$baseUrl/api/health'))
        .timeout(const Duration(seconds: 5));
    return response.statusCode == 200;
  } catch (e) {
    return false;
  }
}
