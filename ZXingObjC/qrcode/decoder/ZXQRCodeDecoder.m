/*
 * Copyright 2012 ZXing authors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import "ZXBitMatrix.h"
#import "ZXByteArray.h"
#import "ZXDecoderResult.h"
#import "ZXErrorCorrectionLevel.h"
#import "ZXErrors.h"
#import "ZXFormatInformation.h"
#import "ZXGenericGF.h"
#import "ZXIntArray.h"
#import "ZXQRCodeBitMatrixParser.h"
#import "ZXQRCodeDataBlock.h"
#import "ZXQRCodeDecodedBitStreamParser.h"
#import "ZXQRCodeDecoder.h"
#import "ZXQRCodeDecoderMetaData.h"
#import "ZXQRCodeVersion.h"
#import "ZXReedSolomonDecoder.h"

@interface ZXQRCodeDecoder ()

@property (nonatomic, strong) ZXReedSolomonDecoder *rsDecoder;

@end

@implementation ZXQRCodeDecoder

- (id)init {
  if (self = [super init]) {
    _rsDecoder = [[ZXReedSolomonDecoder alloc] initWithField:[ZXGenericGF QrCodeField256]];
  }

  return self;
}

- (ZXDecoderResult *)decode:(BOOL **)image length:(unsigned int)length error:(NSError **)error {
  return [self decode:image length:length hints:nil error:error];
}

/**
 * Convenience method that can decode a QR Code represented as a 2D array of booleans.
 * "true" is taken to mean a black module.
 */
- (ZXDecoderResult *)decode:(BOOL **)image length:(unsigned int)length hints:(ZXDecodeHints *)hints error:(NSError **)error {
  int dimension = length;
  ZXBitMatrix *bits = [[ZXBitMatrix alloc] initWithDimension:dimension];
  for (int i = 0; i < dimension; i++) {
    for (int j = 0; j < dimension; j++) {
      if (image[i][j]) {
        [bits setX:j y:i];
      }
    }
  }

  return [self decodeMatrix:bits hints:hints error:error];
}

- (ZXDecoderResult *)decodeMatrix:(ZXBitMatrix *)bits error:(NSError **)error {
  return [self decodeMatrix:bits hints:nil error:error];
}

/**
 * Decodes a QR Code represented as a {@link BitMatrix}. A 1 or "true" is taken to mean a black module.
 */
- (ZXDecoderResult *)decodeMatrix:(ZXBitMatrix *)bits hints:(ZXDecodeHints *)hints error:(NSError **)error {
  ZXQRCodeBitMatrixParser *parser = [[ZXQRCodeBitMatrixParser alloc] initWithBitMatrix:bits error:error];
  if (!parser) {
    return nil;
  }
  ZXDecoderResult *result = [self decodeParser:parser hints:hints error:error];
  if (result) {
    return result;
  }

  // Revert the bit matrix
  [parser remask];

  // Will be attempting a mirrored reading of the version and format info.
  [parser setMirror:YES];

  // Preemptively read the version.
  if (![parser readVersionWithError:error]) {
    return nil;
  }

  /*
   * Since we're here, this means we have successfully detected some kind
   * of version and format information when mirrored. This is a good sign,
   * that the QR code may be mirrored, and we should try once more with a
   * mirrored content.
   */
  // Prepare for a mirrored reading.
  [parser mirror];

  result = [self decodeParser:parser hints:hints error:error];
  if (!result) {
    return nil;
  }

  // Success! Notify the caller that the code was mirrored.
  result.other = [[ZXQRCodeDecoderMetaData alloc] initWithMirrored:YES];

  return result;
}

- (ZXDecoderResult *)decodeParser:(ZXQRCodeBitMatrixParser *)parser hints:(ZXDecodeHints *)hints error:(NSError **)error {
  ZXQRCodeVersion *version = [parser readVersionWithError:error];
  if (!version) {
    return nil;
  }
  ZXFormatInformation *formatInfo = [parser readFormatInformationWithError:error];
  if (!formatInfo) {
    return nil;
  }
  ZXErrorCorrectionLevel *ecLevel = formatInfo.errorCorrectionLevel;

  ZXByteArray *codewords = [parser readCodewordsWithError:error];
  if (!codewords) {
    return nil;
  }
  NSArray *dataBlocks = [ZXQRCodeDataBlock dataBlocks:codewords version:version ecLevel:ecLevel];

  int totalBytes = 0;
  for (ZXQRCodeDataBlock *dataBlock in dataBlocks) {
    totalBytes += dataBlock.numDataCodewords;
  }

  if (totalBytes == 0) {
    return nil;
  }

  ZXByteArray *resultBytes = [[ZXByteArray alloc] initWithLength:totalBytes];
  int resultOffset = 0;

  for (ZXQRCodeDataBlock *dataBlock in dataBlocks) {
    ZXByteArray *codewordBytes = dataBlock.codewords;
    int numDataCodewords = [dataBlock numDataCodewords];
    if (![self correctErrors:codewordBytes numDataCodewords:numDataCodewords error:error]) {
      return nil;
    }
    for (int i = 0; i < numDataCodewords; i++) {
      resultBytes.array[resultOffset++] = codewordBytes.array[i];
    }
  }

  return [ZXQRCodeDecodedBitStreamParser decode:resultBytes version:version ecLevel:ecLevel hints:hints error:error];
}


/**
 * Given data and error-correction codewords received, possibly corrupted by errors, attempts to
 * correct the errors in-place using Reed-Solomon error correction.
 */
- (BOOL)correctErrors:(ZXByteArray *)codewordBytes numDataCodewords:(int)numDataCodewords error:(NSError **)error {
  int numCodewords = (int)codewordBytes.length;
  // First read into an array of ints
  ZXIntArray *codewordsInts = [[ZXIntArray alloc] initWithLength:numCodewords];
  for (int i = 0; i < numCodewords; i++) {
    codewordsInts.array[i] = codewordBytes.array[i] & 0xFF;
  }
  int numECCodewords = (int)codewordBytes.length - numDataCodewords;
  NSError *decodeError = nil;
  if (![self.rsDecoder decode:codewordsInts twoS:numECCodewords error:&decodeError]) {
    if (decodeError.code == ZXReedSolomonError) {
      if (error) *error = ChecksumErrorInstance();
      return NO;
    } else {
      if (error) *error = decodeError;
      return NO;
    }
  }
  // Copy back into array of bytes -- only need to worry about the bytes that were data
  // We don't care about errors in the error-correction codewords
  for (int i = 0; i < numDataCodewords; i++) {
    codewordBytes.array[i] = (int8_t) codewordsInts.array[i];
  }
  return YES;
}

@end
