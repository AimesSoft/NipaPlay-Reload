## Native SMB/CIFS client library written in Dart for Dart

Library support streaming operation and RandomAccessFile. Extremely fast, can be used for streaming music and video. Supported dialects: SMB 1.0, CIFS, SMB 2.0, SMB 2.1.

See [example](example/) directory for examples and usage.

### Usage

#### Create connection

```dart
    final connect = await SmbConnect.connectAuth(
      host: "192.168.1.100",
      domain: "",
      username: "vadim",
      password: "password",
    );
```

#### List of Samba Shares

```dart
    List<SmbFile> shares = await connect.listShares();
    print(shares.map((e) => e.path));
```

#### Get list of files and folders

```dart
    SmbFile folder = await connect.file("/public/");
    List<SmbFile> files = await connect.listFiles(folder);
    print(files.map((e) => e.path));
```

#### Create folder

```dart
    SmbFile folder = await connect.createFolder("/public/folder");
```

#### Create empty file

```dart
    SmbFile file = await connect.createFile("/public/test.txt");
```

#### Stream read

```dart
    SmbFile file = await connect.file("/music/file.mp3");
    Stream<Uint8List> reader = await connect.openRead(file);
    reader.listen((event) {
        print("Read: ${event.length}");
    }, onDone: () {
        print("File readed");
    },  onError: (e) {
        print("Error $e");
    });
```

#### Stream write

```dart
    SmbFile file2 = await connect.createFile("/public/test.txt");
    IOSink writer = await connect.openWrite(file2);
    writer.add(utf8.encode("Lorem ipsum dolor sit amet"));
    await writer.flush();
    await writer.close();
```

#### Delete file/folder

```dart
    await connect.delete(file2);
```

#### Rename file/folder

```dart
    SmbFile file = await connect.file("/public/test.txt");
    await connect.rename(file, "/public/test1.txt");
```

#### Random access file

```dart
    SmbFile file3 = await connect.file("/music/file.mp3");
    RandomAccessFile raf = await connect.open(file3);
    var buf = await raf.read(10);
    await raf.close();
```

#### Close connection

```dart
    await connect.close();
```

### Known issues

 - Flutter version ~3.22.x build broken release version (for ios checked). Solution: upgrade flutter to version ~3.27.x.