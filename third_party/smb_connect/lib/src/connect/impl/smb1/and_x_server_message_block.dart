import 'dart:typed_data';

import 'package:smb_connect/src/exceptions.dart';
import 'package:smb_connect/src/configuration.dart';
import 'package:smb_connect/src/connect/common/common_server_message_block_response.dart';
import 'package:smb_connect/src/connect/impl/smb1/com/smb_com_nt_create_and_x_response.dart';
import 'package:smb_connect/src/connect/impl/smb1/smb_com_constants.dart';
import 'package:smb_connect/src/connect/smb_util.dart';
import 'package:smb_connect/src/utils/extensions.dart';
import 'package:smb_connect/src/utils/strings.dart';

import 'server_message_block.dart';

abstract class AndXServerMessageBlock extends ServerMessageBlock {
  static const int ANDX_COMMAND_OFFSET = 1;
  static const int ANDX_RESERVED_OFFSET = 2;
  static const int ANDX_OFFSET_OFFSET = 3;

  int andxCommand = 0xFF;
  int andxOffset = 0;

  ServerMessageBlock? andx;

  AndXServerMessageBlock(super.config, {super.command, String? name, this.andx})
      : super(path: name) {
    if (andx != null) {
      andxCommand = andx!.getCommand();
    }
  }

  @override
  ServerMessageBlock? getNext() {
    return andx;
  }

  @override
  ServerMessageBlock? getNextResponse() {
    return andx;
  }

  int getBatchLimit(Configuration cfg, int cmd) {
    ///
    /// the default limit is 0 batched messages before this
    /// one, meaning this message cannot be batched.
    return 0;
  }

  ///
  /// We overload this method from ServerMessageBlock because
  /// we want writeAndXWireFormat to write the parameterWords
  /// and bytes. This is so we can write batched smbs because
  /// all but the first smb of the chaain do not have a header
  /// and therefore we do not want to writeHeaderWireFormat. We
  /// just recursivly call writeAndXWireFormat.
  ////

  @override
  int encode(Uint8List dst, int dstIndex) {
    int start = headerStart = dstIndex;

    dstIndex += writeHeaderWireFormat(dst, dstIndex);
    dstIndex += writeAndXWireFormat(dst, dstIndex);
    length = dstIndex - start;

    digest?.sign(dst, headerStart, length, this,
        getResponse() as CommonServerMessageBlockResponse?);

    return length;
  }

  ///
  /// We overload this because we want readAndXWireFormat to
  /// read the parameter words and bytes. This is so when
  /// commands are batched together we can recursivly call
  /// readAndXWireFormat without reading the non-existent header.
  ////

  @override
  int decode(Uint8List buffer, int bufferIndex) {
    int start = headerStart = bufferIndex;

    bufferIndex += readHeaderWireFormat(buffer, bufferIndex);
    bufferIndex += readAndXWireFormat(buffer, bufferIndex);

    int len = bufferIndex - start;
    length = len;

    if (isRetainPayload()) {
      Uint8List payload = Uint8List(len);
      byteArrayCopy(
          src: buffer, srcOffset: 4, dst: payload, dstOffset: 0, length: len);
      setRawPayload(payload);
    }

    if (!verifySignature(buffer, 4, len)) {
      throw SmbProtocolDecodingException(
          "Signature verification failed for ${runtimeType.toString()}");
    }
    return len;
  }

  int writeAndXWireFormat(Uint8List dst, int dstIndex) {
    int start = dstIndex;

    wordCount =
        writeParameterWordsWireFormat(dst, start + ANDX_OFFSET_OFFSET + 2);
    wordCount += 4; // for command, reserved, and offset
    dstIndex += wordCount + 1;
    wordCount = wordCount ~/ 2;
    dst[start] = (wordCount & 0xFF);

    byteCount = writeBytesWireFormat(dst, dstIndex + 2);
    dst[dstIndex++] = (byteCount & 0xFF);
    dst[dstIndex++] = ((byteCount >> 8) & 0xFF);
    dstIndex += byteCount;

    ///
    /// Normally, without intervention everything would batch
    /// with everything else. If the below clause evaluates true
    /// the andx command will not be written and therefore the
    /// response will not read a batched command and therefore
    /// the 'received' member of the response object will not
    /// be set to true indicating the send and sendTransaction
    /// methods that the next part should be sent. This is a
    /// very indirect and simple batching control mechanism.
    if (andx == null ||
        !config.isUseBatching ||
        batchLevel >= getBatchLimit(config, andx!.getCommand())) {
      andxCommand = 0xFF;
      andx = null;

      dst[start + ANDX_COMMAND_OFFSET] = 0xFF;
      dst[start + ANDX_RESERVED_OFFSET] = 0x00;
      // dst[start + ANDX_OFFSET_OFFSET] = 0x00;
      // dst[start + ANDX_OFFSET_OFFSET + 1] = 0x00;
      dst[start + ANDX_OFFSET_OFFSET] = 0xde;
      dst[start + ANDX_OFFSET_OFFSET + 1] = 0xde;

      // andx not used; return
      return dstIndex - start;
    }

    ///
    /// The message provided to batch has a batchLimit that is
    /// higher than the current batchLevel so we will now encode
    /// that chained message. Before doing so we must increment
    /// the batchLevel of the andx message in case it itself is an
    /// andx message and needs to perform the same check as above.
    andx!.batchLevel = batchLevel + 1;

    dst[start + ANDX_COMMAND_OFFSET] = andxCommand;
    dst[start + ANDX_RESERVED_OFFSET] = 0x00;
    andxOffset = dstIndex - headerStart;
    SMBUtil.writeInt2(andxOffset, dst, start + ANDX_OFFSET_OFFSET);

    andx!.setUseUnicode(isUseUnicode());
    if (andx is AndXServerMessageBlock) {
      ///
      /// A word about communicating header info to andx smbs
      ///
      /// This is where we recursively invoke the provided andx smb
      /// object to write it's parameter words and bytes to our outgoing
      /// array. Incedentally when these andx smbs are created they are not
      /// necessarily populated with header data because they're not writing
      /// the header, only their body. But for whatever reason one might wish
      /// to populate fields if the writeXxx operation needs this header data
      /// for whatever reason. I copy over the uid here so it appears correct
      /// in logging output. Logging of andx segments of messages inadvertantly
      /// print header information because of the way toString always makes a
      /// super.toString() call(see toString() at the end of all smbs classes).
      andx!.uid = uid;
      dstIndex +=
          (andx as AndXServerMessageBlock).writeAndXWireFormat(dst, dstIndex);
    } else {
      // the andx smb is not of type andx so lets just write it here and
      // were done.
      int andxStart = dstIndex;
      andx!.wordCount = andx!.writeParameterWordsWireFormat(dst, dstIndex);
      dstIndex += andx!.wordCount + 1;
      andx!.wordCount = andx!.wordCount ~/ 2;
      dst[andxStart] = (andx!.wordCount & 0xFF);

      andx!.byteCount = andx!.writeBytesWireFormat(dst, dstIndex + 2);
      dst[dstIndex++] = (andx!.byteCount & 0xFF);
      dst[dstIndex++] = ((andx!.byteCount >> 8) & 0xFF);
      dstIndex += andx!.byteCount;
    }

    return dstIndex - start;
  }

  int readAndXWireFormat(Uint8List buffer, int bufferIndex) {
    int start = bufferIndex;

    wordCount = buffer[bufferIndex++];

    if (wordCount != 0) {
      ///
      /// these fields are common to all andx commands
      /// so let's populate them here
      andxCommand = buffer[bufferIndex];
      andxOffset = SMBUtil.readInt2(buffer, bufferIndex + 2);

      if (andxOffset == 0) {
        /// Snap server workaround */
        andxCommand = 0xFF;
      }

      ///
      /// no point in calling readParameterWordsWireFormat if there are no more
      /// parameter words. besides, win98 doesn't return "OptionalSupport" field
      if (wordCount > 2) {
        readParameterWordsWireFormat(buffer, bufferIndex + 4);

        ///
        /// The SMB_COM_NT_CREATE_ANDX response wordCount is wrong. There's an
        /// extra 16 bytes for some "Offline Files (CSC or Client Side Caching)"
        /// junk. We need to bump up the wordCount here so that this method returns
        /// the correct number of bytes for signing purposes. Otherwise we get a
        /// signing verification failure.
        if (getCommand() == SmbComConstants.SMB_COM_NT_CREATE_ANDX &&
            (this as SmbComNTCreateAndXResponse).isExtended() &&
            (this as SmbComNTCreateAndXResponse).getFileType() != 1) {
          wordCount += 8;
        }
      }

      bufferIndex = start + 1 + (wordCount * 2);
    }

    byteCount = SMBUtil.readInt2(buffer, bufferIndex);
    bufferIndex += 2;

    if (byteCount != 0) {
      readBytesWireFormat(buffer, bufferIndex);
      bufferIndex += byteCount;
    }

    ///
    /// if there is an andx and it itself is an andx then just recur by
    /// calling this method for it. otherwise just read it's parameter words
    /// and bytes as usual. Note how we can't just call andx.readWireFormat
    /// because there's no header.
    final andx = this.andx;
    if (errorCode != 0 || andxCommand == 0xFF) {
      andxCommand = 0xFF;
      this.andx = null;
    } else if (andx == null) {
      andxCommand = 0xFF;
      throw SmbRuntimeException("no andx command supplied with response");
    } else {
      ///
      /// Set bufferIndex according to andxOffset
      bufferIndex = headerStart + andxOffset;

      andx.headerStart = headerStart;
      andx.setCommand(andxCommand);
      andx.setErrorCode(getErrorCode());
      andx.setFlags(getFlags());
      andx.setFlags2(getFlags2());
      andx.setTid(getTid());
      andx.setPid(getPid());
      andx.setUid(getUid());
      andx.setMid(getMid());
      andx.setUseUnicode(isUseUnicode());

      if (andx is AndXServerMessageBlock) {
        bufferIndex += andx.readAndXWireFormat(buffer, bufferIndex);
      } else {
        ///
        /// Just a plain smb. Read it as normal.
        buffer[bufferIndex++] = (andx.wordCount & 0xFF);

        if (andx.wordCount != 0) {
          ///
          /// no point in calling readParameterWordsWireFormat if there are no more
          /// parameter words. besides, win98 doesn't return "OptionalSupport" field
          if (andx.wordCount > 2) {
            bufferIndex +=
                andx.readParameterWordsWireFormat(buffer, bufferIndex);
          }
        }

        andx.byteCount = SMBUtil.readInt2(buffer, bufferIndex);
        bufferIndex += 2;

        if (andx.byteCount != 0) {
          andx.readBytesWireFormat(buffer, bufferIndex);
          bufferIndex += andx.byteCount;
        }
      }
      andx.setReceived();
    }

    return bufferIndex - start;
  }

  @override
  String toString() {
    return "${super.toString()},andxCommand=0x${Hexdump.toHexString(andxCommand, 2)},andxOffset=$andxOffset";
  }
}
