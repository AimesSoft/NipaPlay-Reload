import 'dart:typed_data';

import 'package:pointycastle/export.dart';
import 'package:smb_connect/src/utils/extensions.dart';

/// This class represents the symmetric algorithms in its various modes
/// (<code>ECB</code>, <code>CFB</code>, <code>OFB</code>, <code>CBC</code>,
/// <code>PCBC</code>, <code>CTR</code>, and <code>CTS</code>) and
/// padding schemes (<code>PKCS5Padding</code>, <code>NoPadding</code>,
/// <code>ISO10126Padding</code>).
///
/// @author Gigi Ankeny
/// @author Jan Luehe
/// @see ElectronicCodeBook
/// @see CipherFeedback
/// @see OutputFeedback
/// @see CipherBlockChaining
/// @see PCBC
/// @see CounterMode
/// @see CipherTextStealing
class DESCipherInternal implements StreamCipher {
  /// internal buffer
  late Uint8List buffer;

  /// block size of cipher in bytes
  int blockSize = 0;

  /// unit size (number of input bytes that can be processed at a time)
  int unitBytes = 0;

  /// index of the content size left in the buffer
  int buffered = 0;

  /// minimum number of bytes in the buffer required for
  /// FeedbackCipher.encryptFinal()/decryptFinal() call.
  /// update() must buffer this many bytes before starting
  /// to encrypt/decrypt data.
  /// currently, only the following cases have non-zero values:
  /// 1) CTS mode - due to its special handling on the last two blocks
  /// (the last one may be incomplete).
  int minBytes = 0;

  /// number of bytes needed to make the total input length a multiple
  /// of the blocksize (this is used in feedback mode, when the number of
  /// input bytes that are processed at a time is different from the block
  /// size)
  int diffBlocksize = 0;

  /// padding class
  Padding? padding;

  /// internal cipher engine
  // FeedbackCipher? cipher;
  ECBBlockCipher? cipher;

  /// the cipher mode
  int cipherMode = ECB_MODE;

  /// are we encrypting or decrypting?
  bool decrypting = false;

  @override
  String get algorithmName => throw UnimplementedError();

  /// Block Mode constants
  static const int ECB_MODE = 0;
  static const int CBC_MODE = 1;
  static const int CFB_MODE = 2;
  static const int OFB_MODE = 3;
  static const int PCBC_MODE = 4;
  static const int CTR_MODE = 5;
  static const int CTS_MODE = 6;

  /// Creates an instance of CipherCore with default ECB mode and
  /// PKCS5Padding.
  DESCipherInternal(BlockCipher impl, int blkSize) {
    blockSize = blkSize;
    unitBytes = blkSize;
    diffBlocksize = blkSize;

    /// The buffer should be usable for all cipher mode and padding
    /// schemes. Thus, it has to be at least (blockSize+1) for CTS.
    /// In decryption mode, it also hold the possible padding block.

    buffer = Uint8List(blockSize * 2); // new byte[blockSize*2];

    // set mode and padding
    cipher = ECBBlockCipher(impl); //ElectronicCodeBook(impl);
    // padding = PKCS5Padding(blockSize);
  }

  static int getNumOfUnit(String mode, int offset, int blockSize) {
    int result = blockSize; // use blockSize as default value
    if (mode.length > offset) {
      final numInt = int.tryParse(mode.substring(offset));
      if (numInt == null) {
        throw Exception("Algorithm mode: $mode not implemented");
      }
      result = numInt >> 3;
      if ((numInt % 8 != 0) || (result > blockSize)) {
        throw Exception("Invalid algorithm mode: $mode");
      }
    }
    return result;
  }

  ///
  /// Initializes this cipher with a key, a set of
  /// algorithm parameters, and a source of randomness.
  ///
  /// <p>The cipher is initialized for one of the following four operations:
  /// encryption, decryption, key wrapping or key unwrapping, depending on
  /// the value of <code>opmode</code>.
  ///
  /// <p>If this cipher (including its underlying feedback or padding scheme)
  /// requires any random bytes, it will get them from <code>random</code>.
  ///
  /// @param opmode the operation mode of this cipher (this is one of
  /// the following:
  /// <code>ENCRYPT_MODE</code>, <code>DECRYPT_MODE</code>,
  /// <code>WRAP_MODE</code> or <code>UNWRAP_MODE</code>)
  /// @param key the encryption key
  /// @param params the algorithm parameters
  /// @param random the source of randomness
  ///
  /// @exception InvalidKeyException if the given key is inappropriate for
  /// initializing this cipher
  /// @exception InvalidAlgorithmParameterException if the given algorithm
  /// parameters are inappropriate for this cipher
  @override
  void init(bool forEncryption, CipherParameters? key) {
    decrypting = !forEncryption;
    // if (key is KeyParameter) {
    //   Uint8List keyBytes = key.key;
    // }
    //, AlgorithmParameterSpec params, SecureRandom random throws InvalidKeyException, InvalidAlgorithmParameterException {
    // decrypting = (opmode == Cipher.DECRYPT_MODE)
    // || (opmode == Cipher.UNWRAP_MODE);

    //     Uint8List keyBytes = getKeyBytes(key);
    //     Uint8List ivBytes = null;
    //     try {
    //         if (params != null) {
    //             if (params instanceof IvParameterSpec) {
    //                 ivBytes = ((IvParameterSpec) params).getIV();
    //                 if ((ivBytes == null) || (ivBytes.length != blockSize)) {
    //                     throw Exception("Wrong IV length: must be $blockSize bytes long");//InvalidAlgorithmParameterException
    //                 }
    //             } else if (params instanceof RC2ParameterSpec) {
    //                 ivBytes = ((RC2ParameterSpec) params).getIV();
    //                 if ((ivBytes != null) && (ivBytes.length != blockSize)) {
    //                     throw Exception("Wrong IV length: must be $blockSize bytes long");//InvalidAlgorithmParameterException
    //                 }
    //             } else {
    //                 throw Exception("Unsupported parameter: $params");//InvalidAlgorithmParameterException
    //             }
    //         }
    //         if (cipherMode == ECB_MODE) {
    //             if (ivBytes != null) {
    //                 throw Exception("ECB mode cannot use IV");//InvalidAlgorithmParameterException
    //             }
    //         } else if (ivBytes == null) {
    //             if (decrypting) {
    //                 throw Exception("Parameters missing");//InvalidAlgorithmParameterException
    //             }

    //             if (random == null) {
    //                 random = SunJCE.getRandom();
    //             }

    //             ivBytes = new byte[blockSize];
    //             random.nextBytes(ivBytes);
    //         }

    buffered = 0;
    diffBlocksize = blockSize;

    cipher!.init(forEncryption, key);
  }

  /// Continues a multiple-part encryption or decryption operation
  /// (depending on how this cipher was initialized), processing another data
  /// part.
  ///
  /// <p>The first <code>inputLen</code> bytes in the <code>input</code>
  /// buffer, starting at <code>inputOffset</code>, are processed, and the
  /// result is stored in the <code>output</code> buffer, starting at
  /// <code>outputOffset</code>.
  ///
  /// @param input the input buffer
  /// @param inputOffset the offset in <code>input</code> where the input
  /// starts
  /// @param inputLen the input length
  /// @param output the buffer for the result
  /// @param outputOffset the offset in <code>output</code> where the result
  /// is stored
  ///
  /// @return the number of bytes stored in <code>output</code>
  ///
  /// @exception ShortBufferException if the given output buffer is too small
  /// to hold the result
  @override
  void processBytes(
      Uint8List inp, int inpOff, int len0, Uint8List out, int outOff) {
    //     // figure out how much can be sent to crypto function
    // int len = buffered + inputLen;
    //     len -= minBytes;
    //     if (padding != null && decrypting) {
    //         // do not include the padding bytes when decrypting
    //         len -= blockSize;
    //     }
    //     // do not count the trailing bytes which do not make up a unit
    //     len = (len > 0 ? (len - (len % unitBytes)) : 0);

    //     // check output buffer capacity
    //     if (output == null || (output.length - outputOffset) < len) {
    //         throw Exception("Output buffer must be (at least) $len bytes long");//ShortBufferException
    //     }

    //     int outLen = 0;
    //     if (len != 0) { // there is some work to do
    //         if ((input == output)
    //              && (outputOffset - inputOffset < inputLen)
    //              && (inputOffset - outputOffset < buffer.length)) {
    //             // copy 'input' out to avoid its content being
    //             // overwritten prematurely.
    //             input = Arrays.copyOfRange(input, inputOffset,
    //                 inputOffset + inputLen);
    //             inputOffset = 0;
    //         }
    //         if (len <= buffered) {
    //             // all to-be-processed data are from 'buffer'
    //             if (decrypting) {
    //                 outLen = cipher.decrypt(buffer, 0, len, output, outputOffset);
    //             } else {
    //                 outLen = cipher.encrypt(buffer, 0, len, output, outputOffset);
    //             }
    //             buffered -= len;
    //             if (buffered != 0) {
    //                 System.arraycopy(buffer, len, buffer, 0, buffered);
    //             }
    //         } else { // len > buffered
    //             int inputConsumed = len - buffered;
    //             int temp;
    //             if (buffered > 0) {
    //                 int bufferCapacity = buffer.length - buffered;
    //                 if (bufferCapacity != 0) {
    //                     temp = min(bufferCapacity, inputConsumed);
    //                     if (unitBytes != blockSize) {
    //                         temp -= ((buffered + temp) % unitBytes);
    //                     }
    //                     System.arraycopy(input, inputOffset, buffer, buffered, temp);
    //                     inputOffset = inputOffset + temp;
    //                     inputConsumed -= temp;
    //                     inputLen -= temp;
    //                     buffered = buffered + temp;
    //                 }
    //                 // process 'buffer'. When finished we can null out 'buffer'
    //                 // Only necessary to null out if buffer holds data for encryption
    //                 if (decrypting) {
    //                      outLen = cipher.decrypt(buffer, 0, buffered, output, outputOffset);
    //                 } else {
    //                      outLen = cipher.encrypt(buffer, 0, buffered, output, outputOffset);
    //                      //encrypt mode. Zero out internal (input) buffer
    //                      Arrays.fill(buffer, (byte) 0x00);
    //                 }
    //                 outputOffset = outputOffset + outLen;
    //                 buffered = 0;
    //             }
    //             if (inputConsumed > 0) { // still has input to process
    //                 if (decrypting) {
    //                     outLen += cipher.decrypt(input, inputOffset, inputConsumed,
    //                         output, outputOffset);
    //                 } else {
    //                     outLen += cipher.encrypt(input, inputOffset, inputConsumed,
    //                         output, outputOffset);
    //                 }
    //                 inputOffset += inputConsumed;
    //                 inputLen -= inputConsumed;
    //             }
    //         }
    //         // Let's keep track of how many bytes are needed to make
    //         // the total input length a multiple of blocksize when
    //         // padding is applied
    //         if (unitBytes != blockSize) {
    //             if (len < diffBlocksize) {
    //                 diffBlocksize -= len;
    //             } else {
    //                 diffBlocksize = blockSize -
    //                     ((len - diffBlocksize) % blockSize);
    //             }
    //         }
    //     }
    //     // Store remaining input into 'buffer' again
    //     if (inputLen > 0) {
    //         System.arraycopy(input, inputOffset, buffer, buffered,
    //                          inputLen);
    //         buffered = buffered + inputLen;
    //     }
    //     return outLen;
  }

  ///
  /// Encrypts or decrypts data in a single-part operation,
  /// or finishes a multiple-part operation.
  /// The data is encrypted or decrypted, depending on how this cipher was
  /// initialized.
  ///
  /// <p>The first <code>inputLen</code> bytes in the <code>input</code>
  /// buffer, starting at <code>inputOffset</code>, and any input bytes that
  /// may have been buffered during a previous <code>update</code> operation,
  /// are processed, with padding (if requested) being applied.
  /// The result is stored in a new buffer.
  ///
  /// <p>The cipher is reset to its initial state (uninitialized) after this
  /// call.
  ///
  /// @param input the input buffer
  /// @param inputOffset the offset in <code>input</code> where the input
  /// starts
  /// @param inputLen the input length
  ///
  /// @return the new buffer with the result
  ///
  /// @exception IllegalBlockSizeException if this cipher is a block cipher,
  /// no padding has been requested (only in encryption mode), and the total
  /// input length of the data processed by this cipher is not a multiple of
  /// block size
  /// @exception BadPaddingException if this cipher is in decryption mode,
  /// and (un)padding has been requested, but the decrypted data is not
  /// bounded by the appropriate padding bytes
  @override
  Uint8List process(Uint8List data) {
    Uint8List output = Uint8List(data.length);
    var finalBuf = prepareInputBuffer(data, 0, data.length, output, 0);
    fillOutputBuffer(finalBuf, 0, output, 0, output.length, data);
    //     try {
    //         Uint8List output = new byte[getOutputSizeByOperation(inputLen, true)];
    //         Uint8List finalBuf = prepareInputBuffer(input, inputOffset,
    //                 inputLen, output, 0);
    //         int finalOffset = (finalBuf == input) ? inputOffset : 0;
    //         int finalBufLen = (finalBuf == input) ? inputLen : finalBuf.length;

    //         int outLen = fillOutputBuffer(finalBuf, finalOffset, output, 0,
    //                 finalBufLen, input);

    endDoFinal();
    //         if (outLen < output.length) {
    //             Uint8List copy = Arrays.copyOf(output, outLen);
    //             if (decrypting) {
    //                 // Zero out internal (output) array
    //                 Arrays.fill(output, (byte) 0x00);
    //             }
    //             return copy;
    //         } else {
    //             return output;
    //         }
    //     } catch (ShortBufferException e) {
    //         // never thrown
    //         throw Exception("Unexpected exception", e);//ProviderException
    //     }
    return output;
  }

  void endDoFinal() {
    buffered = 0;
    diffBlocksize = blockSize;
    if (cipherMode != ECB_MODE) {
      cipher?.reset();
    }
  }

  @override
  void reset() {
    // TODO: implement reset
  }

  @override
  int returnByte(int inp) {
    // TODO: implement returnByte
    throw UnimplementedError();
  }

  Uint8List prepareInputBuffer(Uint8List input, int inputOffset, int inputLen,
      Uint8List output, int outputOffset) {
    // calculate total input length
    int len = buffered + inputLen;
    // calculate padding length
    int totalLen = len;
    int paddingLen = 0;
    // will the total input length be a multiple of blockSize?
    if (unitBytes != blockSize) {
      if (totalLen < diffBlocksize) {
        paddingLen = diffBlocksize - totalLen;
      } else {
        paddingLen = blockSize - ((totalLen - diffBlocksize) % blockSize);
      }
    } else if (padding != null) {
      paddingLen = padding!.padCount(input); // padLength(totalLen);
    }

    if (decrypting &&
        (padding != null) &&
        (paddingLen > 0) &&
        (paddingLen != blockSize)) {
      throw Exception(
          "Input length must be multiple of $blockSize when decrypting with padded cipher"); //IllegalBlockSizeException
    }

    ///
    /// prepare the final input, assemble a new buffer if any
    /// of the following is true:
    ///  - 'input' and 'output' are the same buffer
    ///  - there are internally buffered bytes
    ///  - doing encryption and padding is needed

    if ((buffered != 0) ||
        (!decrypting && padding != null) ||
        ((input == output) &&
            (outputOffset - inputOffset < inputLen) &&
            (inputOffset - outputOffset < buffer.length))) {
      Uint8List finalBuf;
      if (decrypting || padding == null) {
        paddingLen = 0;
      }
      finalBuf = Uint8List(len + paddingLen);
      if (buffered != 0) {
        byteArrayCopy(
            src: buffer,
            srcOffset: 0,
            dst: finalBuf,
            dstOffset: 0,
            length: buffered);
        if (!decrypting) {
          // done with input buffer. We should zero out the
          // data if we're in encrypt mode.
          // Arrays.fill(buffer, (byte) 0x00);
          buffer.fill();
        }
      }
      if (inputLen != 0) {
        byteArrayCopy(
            src: input,
            srcOffset: 0,
            dst: finalBuf,
            dstOffset: buffered,
            length: inputLen);
      }
      if (paddingLen != 0) {
        // padding.padWithLen(
        //     finalBuf, buffered + inputLen, paddingLen);
      }
      return finalBuf;
    }
    return input;
  }

  int fillOutputBuffer(Uint8List finalBuf, int finalOffset, Uint8List output,
      int outOfs, int finalBufLen, Uint8List input) {
    int len;
    try {
      len = finalNoPadding(finalBuf, finalOffset, output, outOfs, finalBufLen);
      if (decrypting && padding != null) {
        // TODO: No padding
        // padding!.process(false, output);
        // len = unpad(len, outOfs, output);
      }
      return len;
    } finally {
      if (!decrypting && finalBuf != input) {
        // done with internal finalBuf array. Copied to output
        finalBuf.fill();
      }
    }
  }

  int finalNoPadding(
      Uint8List? inp, int inOfs, Uint8List out, int outOfs, int len) {
    if (inp == null || len == 0) {
      return 0;
    }
    if ((cipherMode != CFB_MODE) &&
        (cipherMode != OFB_MODE) &&
        ((len % unitBytes) != 0) &&
        (cipherMode != CTS_MODE)) {
      if (padding != null) {
        throw Exception(
            "Input length (with padding) not multiple of $unitBytes bytes"); //IllegalBlockSizeException
      } else {
        throw Exception(
            "Input length not multiple of $unitBytes bytes"); //IllegalBlockSizeException
      }
    }

    for (int i = len; i >= blockSize; i -= blockSize) {
      cipher!.processBlock(inp, inOfs, out, outOfs);
      inOfs += blockSize;
      outOfs += blockSize;
    }
    return len;
  }
}
