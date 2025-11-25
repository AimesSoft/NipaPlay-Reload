import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:smb_connect/smb_connect.dart';

void main() async {
  final connect = await SmbConnect.connectAuth(
    host: "192.168.1.100",
    domain: "",
    username: "<username>",
    password: "<password>",
  );

  // List of Samba Shares
  var shares = await connect.listShares();
  print(shares.map((e) => e.path).join(","));

  // Get list of files and folders
  SmbFile folder = await connect.file("/home");
  List<SmbFile> files = await connect.listFiles(folder);
  print(files.map((e) => e.path).join(","));

  SmbFile folder2 = await connect.createFolder("/home/folder");
  assert(folder2.isDirectory());

  SmbFile file2 = await connect.createFile("/home/folder/test2.txt");
  assert(file2.isExists);

  await connect.delete(folder2);

  // Create empty file
  SmbFile file = await connect.createFile("/home/test.txt");
  print("File is exists: ${file.isExists}");

  // Stream write (for example text data)
  IOSink writer = await connect.openWrite(file);
  writer.add(
      utf8.encode("Lorem ipsum dolor sit amet, consectetur adipiscing elit"));
  await writer.flush();
  await writer.close();
  print("File was changed");

  // Stream read
  Stream<Uint8List> reader = await connect.openRead(file);
  var s = await reader.asyncMap((event) => utf8.decode(event)).join("");
  print("File: $s");

  // Rename file
  file = await connect.rename(file, "/home/test2.txt");
  print(file.path);

  // Delete file
  await connect.delete(file);

  // Close connection
  await connect.close();
  exit(0);
}
