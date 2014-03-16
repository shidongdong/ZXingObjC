/*
 * Copyright 2013 ZXing authors
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

extern const int ZX_AZTEC_DEFAULT_EC_PERCENT;

@class ZXAztecCode, ZXBitArray, ZXGenericGF;

/**
 * Generates Aztec 2D barcodes.
 */
@interface ZXAztecEncoder : NSObject

/**
 * Encodes the given binary content as an Aztec symbol
 *
 * @param data input data string
 * @return Aztec symbol matrix with metadata
 */
+ (ZXAztecCode *)encode:(const int8_t *)data len:(NSUInteger)len;

/**
 * Encodes the given binary content as an Aztec symbol
 *
 * @param data input data string
 * @param minECCPercent minimal percentage of error check words (According to ISO/IEC 24778:2008,
 *                      a minimum of 23% + 3 words is recommended)
 * @return Aztec symbol matrix with metadata
 */
+ (ZXAztecCode *)encode:(const int8_t *)data len:(NSUInteger)len minECCPercent:(int)minECCPercent;

@end
