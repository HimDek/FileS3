import 'package:flutter/material.dart';
import 'package:files3/services/config_manager.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  SettingsPageState createState() => SettingsPageState();
}

class SettingsPageState extends State<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: Icon(Icons.cloud),
            title: Text("AWS S3 Configuration"),
            subtitle: Text(
              "Configure AWS S3 access key, secret key, region, bucket, host etc.",
            ),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (context) => S3ConfigPage())),
          ),
          ListTile(
            leading: Icon(Icons.palette),
            title: Text("Appearance"),
            subtitle: Text(
              "Configure UI settings like theme, colors, font size etc.",
            ),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (context) => UiSettingsPage())),
          ),
        ],
      ),
    );
  }
}
