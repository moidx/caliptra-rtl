// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// AES package

package aes_pkg;

// If this parameter is set, fatal alerts clear all status and trigger bits to zero. By
// default, it's not set, i.e., no clearing is happening, in order to simplify debugging.
parameter bit ClearStatusOnFatalAlert = 1'b0;

// The initial key is always provided in two shares, independently whether the cipher core is
// masked or not.
parameter int unsigned NumSharesKey = 2;

// Software updates IV in chunks of 32 bits, the counter updates 16 bits at a time.
parameter int unsigned SliceSizeCtr = 16;
parameter int unsigned NumSlicesCtr = aes_reg_pkg::NumRegsIv * 32 / SliceSizeCtr;
parameter int unsigned SliceIdxWidth = caliptra_prim_util_pkg::vbits(NumSlicesCtr);

// In GCM, the counter performs inc32() instead of inc128(), i.e., the counter wraps at 32 bits.
parameter int unsigned SliceIdxMaxInc32 = 32 / SliceSizeCtr - 1;

// Widths of signals carrying pseudo-random data for clearing
parameter int unsigned WidthPRDClearing = 64;
parameter int unsigned NumChunksPRDClearing128 = 128/WidthPRDClearing;
parameter int unsigned NumChunksPRDClearing256 = 256/WidthPRDClearing;

// Widths of signals carrying pseudo-random data for masking
parameter int unsigned WidthPRDSBox     = 8;  // Number PRD bits per S-Box. This includes the
                                              // 8 bits for the output mask when using any of the
                                              // masked Canright S-Box implementations.
parameter int unsigned WidthPRDData     = 16*WidthPRDSBox; // 16 S-Boxes for the data path
parameter int unsigned WidthPRDKey      = 4*WidthPRDSBox;  // 4 S-Boxes for the key expand
parameter int unsigned WidthPRDMasking  = WidthPRDData + WidthPRDKey;

// Clearing PRNG default LFSR seed and permutation
// These LFSR parameters have been generated with
// $ util/design/gen-lfsr-seed.py --width 64 --seed 31468618 --prefix "Clearing"
parameter int ClearingLfsrWidth = 64;
typedef logic [ClearingLfsrWidth-1:0] clearing_lfsr_seed_t;
typedef logic [ClearingLfsrWidth-1:0][$clog2(ClearingLfsrWidth)-1:0] clearing_lfsr_perm_t;
parameter clearing_lfsr_seed_t RndCnstClearingLfsrSeedDefault = 64'hc32d580f74f1713a;
parameter clearing_lfsr_perm_t RndCnstClearingLfsrPermDefault = {
  128'hb33fdfc81deb6292c21f8a3102585067,
  256'h9c2f4be1bbe937b4b7c9d7f4e57568d99c8ae291a899143e0d8459d31b143223
};
// A second permutation is needed for the second share.
parameter clearing_lfsr_perm_t RndCnstClearingSharePermDefault = {
  128'hf66fd61b27847edc2286706fb3a2e900,
  256'h9736b95ac3f3b5205caf8dc536aad73605d393c8dd94476e830e97891d4828d0
};

// Masking PRNG default state seed and output permutation
// The output width is 160 bits (WidthPRDMasking = WidthPRDSBox * (16 + 4)).
// These LFSR parameters have been generated with
// $ util/design/gen-lfsr-seed.py --width 160 --seed 31468618 --prefix "Masking"
parameter int MaskingLfsrWidth = 160; // = WidthPRDMasking = WidthPRDSBox * (16 + 4)
typedef logic [MaskingLfsrWidth-1:0][$clog2(MaskingLfsrWidth)-1:0] masking_lfsr_perm_t;
parameter masking_lfsr_perm_t RndCnstMaskingLfsrPermDefault = {
  256'h17261943423e4c5c03872194050c7e5f8497081d96666d406f4b606473303469,
  256'h8e7c721c8832471f59919e0b128f067b25622768462e554d8970815d490d7f44,
  256'h048c867d907a239b20220f6c79071a852d76485452189f14091b1e744e396737,
  256'h4f785b772b352f6550613c58130a8b104a3f28019c9a380233956b00563a512c,
  256'h808d419d63982a16995e0e3b57826a36718a9329452492533d83115a75316e15
};
// The state width is 177 bits (Bivium) but the primitive expects a 288-bit seed (Trivium).
// These LFSR parameters have been generated with
// $ util/design/gen-lfsr-seed.py --width 288 --seed 31468618 --prefix "Masking"
parameter int MaskingPrngStateWidth = 288;
typedef logic [MaskingPrngStateWidth-1:0] masking_lfsr_seed_t;
parameter masking_lfsr_seed_t RndCnstMaskingLfsrSeedDefault = {
  32'h758a4420,
  256'h31e1c461_6ea343ec_153282a3_0c132b57_23c5a4cf_4743b3c7_c32d580f_74f1713a
};

typedef enum logic [31:0] {
  SBoxImplLut,                   // Unmasked LUT-based S-Box
  SBoxImplCanright,              // Unmasked Canright S-Box, see aes_sbox_canright.sv
  SBoxImplCanrightMasked,        // First-order masked Canright S-Box
                                 // see aes_sbox_canright_masked.sv
  SBoxImplCanrightMaskedNoreuse, // First-order masked Canright S-Box without mask reuse,
                                 // see aes_sbox_canright_masked_noreuse.sv
  SBoxImplDom                    // First-order masked S-Box using domain-oriented masking,
                                 // see aes_sbox_canright_dom.sv
} sbox_impl_e;

// GF(2^128) irreducible, field-generating polynomial for AES-GCM
// See Section "6.3 Multiplication Operation on Blocks" of
// https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-38d.pdf on Page 11:
//   "Let R be the bit string 11100001 || 0^120."
// And further on Page 12:
//   "The reduction modulus is the polynomial of degree 128 that corresponds to R || 1"
// Or in other words: x^128 + x^7 + x^2 + x + 1
// The MSB gets clipped off below.
parameter int unsigned GCMDegree = 128;
parameter bit [GCMDegree-1:0] GCMIPoly = GCMDegree'(1'b1) << 7 |
                                         GCMDegree'(1'b1) << 2 |
                                         GCMDegree'(1'b1) << 1 |
                                         GCMDegree'(1'b1) << 0;

// Parameters used for controlgroups in the coverage
parameter int AES_OP_WIDTH             = 2;
parameter int AES_MODE_WIDTH           = 6;
parameter int AES_KEYLEN_WIDTH         = 3;
parameter int AES_PRNGRESEEDRATE_WIDTH = 3;
parameter int AES_GCMPHASE_WIDTH       = 6;

// SEC_CM: MAIN.CONFIG.SPARSE
typedef enum logic [AES_OP_WIDTH-1:0] {
  AES_ENC = 2'b01,
  AES_DEC = 2'b10
} aes_op_e;

// SEC_CM: MAIN.CONFIG.SPARSE
typedef enum logic [AES_MODE_WIDTH-1:0] {
  AES_ECB  = 6'b00_0001,
  AES_CBC  = 6'b00_0010,
  AES_CFB  = 6'b00_0100,
  AES_OFB  = 6'b00_1000,
  AES_CTR  = 6'b01_0000,
  AES_GCM  = 6'b10_0000,
  AES_NONE = 6'b11_1111
} aes_mode_e;

// SEC_CM: MAIN.CONFIG.SPARSE
typedef enum logic [AES_OP_WIDTH-1:0] {
  CIPH_FWD = 2'b01,
  CIPH_INV = 2'b10
} ciph_op_e;

// SEC_CM: MAIN.CONFIG.SPARSE
typedef enum logic [AES_KEYLEN_WIDTH-1:0] {
  AES_128 = 3'b001,
  AES_192 = 3'b010,
  AES_256 = 3'b100
} key_len_e;

// SEC_CM: MAIN.CONFIG.SPARSE
typedef enum logic [AES_PRNGRESEEDRATE_WIDTH-1:0] {
  PER_1  = 3'b001,
  PER_64 = 3'b010,
  PER_8K = 3'b100
} prs_rate_e;
parameter int unsigned BlockCtrWidth = 13;

// SEC_CM: GCM.CONFIG.SPARSE
typedef enum logic [AES_GCMPHASE_WIDTH-1:0] {
  GCM_INIT    = 6'b00_0001,
  GCM_RESTORE = 6'b00_0010,
  GCM_AAD     = 6'b00_0100,
  GCM_TEXT    = 6'b00_1000,
  GCM_SAVE    = 6'b01_0000,
  GCM_TAG     = 6'b10_0000
} gcm_phase_e;

typedef struct packed {
  logic [31:7] unused;
  logic        alert_fatal_fault;
  logic        alert_recov_ctrl_update_err;
  logic        input_ready;
  logic        output_valid;
  logic        output_lost;
  logic        stall;
  logic        idle;
} status_t;

typedef struct packed {
  logic        recov_ctrl_update_err;
  logic        fatal_fault;
} alert_test_t;

  // Sparse state encodings

  // Encoding generated with:
  // $ ./util/design/sparse-fsm-encode.py -d 3 -m 8 -n 6 \
  //      -s 31468618 --language=sv
  //
  // Hamming distance histogram:
  //
  //  0: --
  //  1: --
  //  2: --
  //  3: |||||||||||||||||||| (57.14%)
  //  4: ||||||||||||||| (42.86%)
  //  5: --
  //  6: --
  //
  // Minimum Hamming distance: 3
  // Maximum Hamming distance: 4
  // Minimum Hamming weight: 1
  // Maximum Hamming weight: 5
  //
  localparam int CipherCtrlStateWidth = 6;
  typedef enum logic [CipherCtrlStateWidth-1:0] {
    CIPHER_CTRL_IDLE        = 6'b001001,
    CIPHER_CTRL_INIT        = 6'b100011,
    CIPHER_CTRL_ROUND       = 6'b111101,
    CIPHER_CTRL_FINISH      = 6'b010000,
    CIPHER_CTRL_PRNG_RESEED = 6'b100100,
    CIPHER_CTRL_CLEAR_S     = 6'b111010,
    CIPHER_CTRL_CLEAR_KD    = 6'b001110,
    CIPHER_CTRL_ERROR       = 6'b010111
  } aes_cipher_ctrl_e;

  // $ ./sparse-fsm-encode.py -d 3 -m 3 -n 5 \
  //      -s 31468618 --language=sv
  //
  // Hamming distance histogram:
  //
  //  0: --
  //  1: --
  //  2: --
  //  3: |||||||||||||||||||| (66.67%)
  //  4: |||||||||| (33.33%)
  //  5: --
  //
  // Minimum Hamming distance: 3
  // Maximum Hamming distance: 4
  //
  localparam int CtrStateWidth = 5;
  typedef enum logic [CtrStateWidth-1:0] {
    CTR_IDLE  = 5'b01110,
    CTR_INCR  = 5'b11000,
    CTR_ERROR = 5'b00001
  } aes_ctr_e;

  // Encoding generated with:
  // $ ./util/design/sparse-fsm-encode.py -d 3 -m 8 -n 6 \
  //      -s 31468618 --language=sv
  //
  // Hamming distance histogram:
  //
  //  0: --
  //  1: --
  //  2: --
  //  3: |||||||||||||||||||| (57.14%)
  //  4: ||||||||||||||| (42.86%)
  //  5: --
  //  6: --
  //
  // Minimum Hamming distance: 3
  // Maximum Hamming distance: 4
  // Minimum Hamming weight: 1
  // Maximum Hamming weight: 5
  //
  localparam int CtrlStateWidth = 6;
  typedef enum logic [CtrlStateWidth-1:0] {
    CTRL_IDLE        = 6'b001001,
    CTRL_LOAD        = 6'b100011,
    CTRL_GHASH_READY = 6'b111101,
    CTRL_PRNG_RESEED = 6'b010000,
    CTRL_FINISH      = 6'b100100,
    CTRL_CLEAR_I     = 6'b111010,
    CTRL_CLEAR_CO    = 6'b001110,
    CTRL_ERROR       = 6'b010111
  } aes_ctrl_e;

// Encoding generated with:
// $ ./util/design/sparse-fsm-encode.py -d 3 -m 9 -n 7 \
//     -s 31468618 --language=sv
//
// Hamming distance histogram:
//
//  0: --
//  1: --
//  2: --
//  3: |||||||||||||||||| (38.89%)
//  4: |||||||||||||||||||| (41.67%)
//  5: |||||||| (16.67%)
//  6: | (2.78%)
//  7: --
//
// Minimum Hamming distance: 3
// Maximum Hamming distance: 6
// Minimum Hamming weight: 1
// Maximum Hamming weight: 5
//
localparam int GhashStateWidth = 7;
typedef enum logic [GhashStateWidth-1:0] {
  GHASH_IDLE                    = 7'b1100001,
  GHASH_MULT                    = 7'b0010001,
  GHASH_ADD_S                   = 7'b0000110,
  GHASH_OUT                     = 7'b0110111,
  GHASH_ERROR                   = 7'b0111010,
  GHASH_MASKED_INIT             = 7'b1111100,
  GHASH_MASKED_ADD_STATE_SHARES = 7'b0101101,
  GHASH_MASKED_ADD_CORR         = 7'b0001000,
  GHASH_MASKED_SETTLE           = 7'b1001111
} aes_ghash_e;

// Generic, sparse mux selector encodings

// Encoding generated with:
// $ ./util/design/sparse-fsm-encode.py -d 3 -m 2 -n 3 \
//      -s 31468618 --language=sv
//
// Hamming distance histogram:
//
//  0: --
//  1: --
//  2: --
//  3: |||||||||||||||||||| (100.00%)
//
// Minimum Hamming distance: 3
// Maximum Hamming distance: 3
// Minimum Hamming weight: 1
// Maximum Hamming weight: 2
//
parameter int Mux2SelWidth = 3;
typedef enum logic [Mux2SelWidth-1:0] {
  MUX2_SEL_0 = 3'b011,
  MUX2_SEL_1 = 3'b100
} mux2_sel_e;

// Encoding generated with:
// $ ./sparse-fsm-encode.py -d 3 -m 3 -n 5 \
//      -s 31468618 --language=sv
//
// Hamming distance histogram:
//
//  0: --
//  1: --
//  2: --
//  3: |||||||||||||||||||| (66.67%)
//  4: |||||||||| (33.33%)
//  5: --
//
// Minimum Hamming distance: 3
// Maximum Hamming distance: 4
//
parameter int Mux3SelWidth = 5;
typedef enum logic [Mux3SelWidth-1:0] {
  MUX3_SEL_0 = 5'b01110,
  MUX3_SEL_1 = 5'b11000,
  MUX3_SEL_2 = 5'b00001
} mux3_sel_e;

// Encoding generated with:
// $ ./sparse-fsm-encode.py -d 3 -m 4 -n 5 \
//      -s 31468618 --language=sv
//
// Hamming distance histogram:
//
//  0: --
//  1: --
//  2: --
//  3: |||||||||||||||||||| (66.67%)
//  4: |||||||||| (33.33%)
//  5: --
//
// Minimum Hamming distance: 3
// Maximum Hamming distance: 4
//
parameter int Mux4SelWidth = 5;
typedef enum logic [Mux4SelWidth-1:0] {
  MUX4_SEL_0 = 5'b01110,
  MUX4_SEL_1 = 5'b11000,
  MUX4_SEL_2 = 5'b00001,
  MUX4_SEL_3 = 5'b10111
} mux4_sel_e;

// Encoding generated with:
// $ ./util/design/sparse-fsm-encode.py -d 3 -m 5 -n 6 \
//     -s 31468618 --language=sv
//
// Hamming distance histogram:
//
//  0: --
//  1: --
//  2: --
//  3: |||||||||||||||||||| (50.00%)
//  4: |||||||||||||||| (40.00%)
//  5: |||| (10.00%)
//  6: --
//
// Minimum Hamming distance: 3
// Maximum Hamming distance: 5
// Minimum Hamming weight: 1
// Maximum Hamming weight: 5
//
localparam int Mux5SelWidth = 6;
typedef enum logic [Mux5SelWidth-1:0] {
  MUX5_SEL_0 = 6'b110000,
  MUX5_SEL_1 = 6'b001000,
  MUX5_SEL_2 = 6'b000011,
  MUX5_SEL_3 = 6'b011101,
  MUX5_SEL_4 = 6'b111110
} mux5_sel_e;


// $ ./sparse-fsm-encode.py -d 3 -m 6 -n 6 \
//      -s 31468618 --language=sv
//
// Hamming distance histogram:
//
//  0: --
//  1: --
//  2: --
//  3: |||||||||||||||||||| (53.33%)
//  4: ||||||||||||||| (40.00%)
//  5: || (6.67%)
//  6: --
//
// Minimum Hamming distance: 3
// Maximum Hamming distance: 5
//
parameter int Mux6SelWidth = 6;
typedef enum logic [Mux6SelWidth-1:0] {
  MUX6_SEL_0 = 6'b011101,
  MUX6_SEL_1 = 6'b110000,
  MUX6_SEL_2 = 6'b001000,
  MUX6_SEL_3 = 6'b000011,
  MUX6_SEL_4 = 6'b111110,
  MUX6_SEL_5 = 6'b100101
} mux6_sel_e;

// Mux selector signal types. These use the generic types defined above.

parameter int DIPSelNum = 2;
parameter int DIPSelWidth = Mux2SelWidth;
typedef enum logic [DIPSelWidth-1:0] {
  DIP_DATA_IN = MUX2_SEL_0,
  DIP_CLEAR   = MUX2_SEL_1
} dip_sel_e;

parameter int SISelNum = 2;
parameter int SISelWidth = Mux2SelWidth;
typedef enum logic [SISelWidth-1:0] {
  SI_ZERO = MUX2_SEL_0,
  SI_DATA = MUX2_SEL_1
} si_sel_e;

parameter int AddSISelNum = 2;
parameter int AddSISelWidth = Mux2SelWidth;
typedef enum logic [AddSISelWidth-1:0] {
  ADD_SI_ZERO = MUX2_SEL_0,
  ADD_SI_IV   = MUX2_SEL_1
} add_si_sel_e;

parameter int StateSelNum = 3;
parameter int StateSelWidth = Mux3SelWidth;
typedef enum logic [StateSelWidth-1:0] {
  STATE_INIT  = MUX3_SEL_0,
  STATE_ROUND = MUX3_SEL_1,
  STATE_CLEAR = MUX3_SEL_2
} state_sel_e;

parameter int AddRKSelNum = 3;
parameter int AddRKSelWidth = Mux3SelWidth;
typedef enum logic [AddRKSelWidth-1:0] {
  ADD_RK_INIT  = MUX3_SEL_0,
  ADD_RK_ROUND = MUX3_SEL_1,
  ADD_RK_FINAL = MUX3_SEL_2
} add_rk_sel_e;

parameter int KeyInitSelNum = 3;
parameter int KeyInitSelWidth = Mux3SelWidth;
typedef enum logic [KeyInitSelWidth-1:0] {
  KEY_INIT_INPUT  = MUX3_SEL_0,
  KEY_INIT_KEYMGR = MUX3_SEL_1,
  KEY_INIT_CLEAR  = MUX3_SEL_2
} key_init_sel_e;

parameter int IVSelNum = 6;
parameter int IVSelWidth = Mux6SelWidth;
typedef enum logic [IVSelWidth-1:0] {
  IV_INPUT        = MUX6_SEL_0,
  IV_DATA_OUT     = MUX6_SEL_1,
  IV_DATA_OUT_RAW = MUX6_SEL_2,
  IV_DATA_IN_PREV = MUX6_SEL_3,
  IV_CTR          = MUX6_SEL_4,
  IV_CLEAR        = MUX6_SEL_5
} iv_sel_e;

parameter int KeyFullSelNum = 4;
parameter int KeyFullSelWidth = Mux4SelWidth;
typedef enum logic [KeyFullSelWidth-1:0] {
  KEY_FULL_ENC_INIT = MUX4_SEL_0,
  KEY_FULL_DEC_INIT = MUX4_SEL_1,
  KEY_FULL_ROUND    = MUX4_SEL_2,
  KEY_FULL_CLEAR    = MUX4_SEL_3
} key_full_sel_e;

parameter int KeyDecSelNum = 2;
parameter int KeyDecSelWidth = Mux2SelWidth;
typedef enum logic [KeyDecSelWidth-1:0] {
  KEY_DEC_EXPAND = MUX2_SEL_0,
  KEY_DEC_CLEAR  = MUX2_SEL_1
} key_dec_sel_e;

parameter int KeyWordsSelNum = 4;
parameter int KeyWordsSelWidth = Mux4SelWidth;
typedef enum logic [KeyWordsSelWidth-1:0] {
  KEY_WORDS_0123 = MUX4_SEL_0,
  KEY_WORDS_2345 = MUX4_SEL_1,
  KEY_WORDS_4567 = MUX4_SEL_2,
  KEY_WORDS_ZERO = MUX4_SEL_3
} key_words_sel_e;

parameter int RoundKeySelNum = 2;
parameter int RoundKeySelWidth = Mux2SelWidth;
typedef enum logic [RoundKeySelWidth-1:0] {
  ROUND_KEY_DIRECT = MUX2_SEL_0,
  ROUND_KEY_MIXED  = MUX2_SEL_1
} round_key_sel_e;

parameter int AddSOSelNum = 3;
parameter int AddSOSelWidth = Mux3SelWidth;
typedef enum logic [AddSOSelWidth-1:0] {
  ADD_SO_ZERO = MUX3_SEL_0,
  ADD_SO_IV   = MUX3_SEL_1,
  ADD_SO_DIP  = MUX3_SEL_2
} add_so_sel_e;

parameter int GHashInSelNum = 2;
parameter int GHashInSelWidth = Mux2SelWidth;
typedef enum logic [GHashInSelWidth-1:0] {
  GHASH_IN_DATA_IN_PREV = MUX2_SEL_0,
  GHASH_IN_DATA_OUT     = MUX2_SEL_1
} ghash_in_sel_e;

parameter int GHashAddInSelWidth = 3;
typedef enum logic [GHashAddInSelWidth-1:0] {
  ADD_IN_GHASH_IN = 3'b001,
  ADD_IN_CORR_A   = 3'b010,
  ADD_IN_CORR_B   = 3'b100,
  ADD_IN_ZERO     = 3'b000
} ghash_add_in_sel_e;

parameter int GHashStateSelNum = 5;
parameter int GHashStateSelWidth = Mux5SelWidth;
typedef enum logic [GHashStateSelWidth-1:0] {
  GHASH_STATE_RESTORE = MUX5_SEL_0,
  GHASH_STATE_INIT    = MUX5_SEL_1,
  GHASH_STATE_ADD     = MUX5_SEL_2,
  GHASH_STATE_ADD_S   = MUX5_SEL_3,
  GHASH_STATE_MULT    = MUX5_SEL_4
} ghash_state_sel_e;

parameter int GFMultInSelWidth = 3;
typedef enum logic [GFMultInSelWidth-1:0] {
  MULT_IN_STATE0 = 3'b001,
  MULT_IN_STATE1 = 3'b010,
  MULT_IN_S1     = 3'b100,
  MULT_IN_ZERO   = 3'b000
} gf_mult_in_sel_e;

parameter int DataOutSelNum = 2;
parameter int DataOutSelWidth = Mux2SelWidth;
typedef enum logic [DataOutSelWidth-1:0] {
  DATA_OUT_CIPHER = MUX2_SEL_0,
  DATA_OUT_GHASH  = MUX2_SEL_1
} data_out_sel_e;

// Sparse two-value signal type sp2v_e
parameter int Sp2VNum = 2;
parameter int Sp2VWidth = Mux2SelWidth;
typedef enum logic [Sp2VWidth-1:0] {
  SP2V_HIGH = MUX2_SEL_0,
  SP2V_LOW  = MUX2_SEL_1
} sp2v_e;

typedef logic [Sp2VWidth-1:0] sp2v_logic_t;
parameter sp2v_logic_t SP2V_LOGIC_HIGH = {SP2V_HIGH};

// Control register type
typedef struct packed {
  logic      manual_operation;
  prs_rate_e prng_reseed_rate;
  logic      sideload;
  key_len_e  key_len;
  aes_mode_e mode;
  aes_op_e   operation;
} ctrl_reg_t;

parameter ctrl_reg_t CTRL_RESET = '{
  manual_operation: aes_reg_pkg::AES_CTRL_SHADOWED_MANUAL_OPERATION_RESVAL,
  prng_reseed_rate: prs_rate_e'(aes_reg_pkg::AES_CTRL_SHADOWED_PRNG_RESEED_RATE_RESVAL),
  sideload:         aes_reg_pkg::AES_CTRL_SHADOWED_SIDELOAD_RESVAL,
  key_len:          key_len_e'(aes_reg_pkg::AES_CTRL_SHADOWED_KEY_LEN_RESVAL),
  mode:             aes_mode_e'(aes_reg_pkg::AES_CTRL_SHADOWED_MODE_RESVAL),
  operation:        aes_op_e'(aes_reg_pkg::AES_CTRL_SHADOWED_OPERATION_RESVAL)
};

// GCM control register type
typedef struct packed {
  logic [4:0] num_valid_bytes;
  gcm_phase_e phase;
} ctrl_gcm_reg_t;

// Multiplication by {02} (i.e. x) on GF(2^8)
// with field generating polynomial {01}{1b} (9'h11b)
// Sometimes also denoted by xtime().
function automatic logic [7:0] aes_mul2(logic [7:0] in);
  logic [7:0] out;
  out[7] = in[6];
  out[6] = in[5];
  out[5] = in[4];
  out[4] = in[3] ^ in[7];
  out[3] = in[2] ^ in[7];
  out[2] = in[1];
  out[1] = in[0] ^ in[7];
  out[0] = in[7];
  return out;
endfunction

// Multiplication by {04} (i.e. x^2) on GF(2^8)
// with field generating polynomial {01}{1b} (9'h11b)
function automatic logic [7:0] aes_mul4(logic [7:0] in);
  return aes_mul2(aes_mul2(in));
endfunction

// Division by {02} (i.e. x) on GF(2^8)
// with field generating polynomial {01}{1b} (9'h11b)
// This is the inverse of aes_mul2() or xtime().
function automatic logic [7:0] aes_div2(logic [7:0] in);
  logic [7:0] out;
  out[7] = in[0];
  out[6] = in[7];
  out[5] = in[6];
  out[4] = in[5];
  out[3] = in[4] ^ in[0];
  out[2] = in[3] ^ in[0];
  out[1] = in[2];
  out[0] = in[1] ^ in[0];
  return out;
endfunction

// Circular byte shift to the left
function automatic logic [31:0] aes_circ_byte_shift(logic [31:0] in, logic [1:0] shift);
  logic [31:0] out;
  logic [31:0] s;
  s = {30'b0,shift};
  out = {in[8*((7-s)%4) +: 8], in[8*((6-s)%4) +: 8],
         in[8*((5-s)%4) +: 8], in[8*((4-s)%4) +: 8]};
  return out;
endfunction

// Transpose state matrix
function automatic logic [3:0][3:0][7:0] aes_transpose(logic [3:0][3:0][7:0] in);
  logic [3:0][3:0][7:0] transpose;
  transpose = '0;
  for (int j = 0; j < 4; j++) begin
    for (int i = 0; i < 4; i++) begin
      transpose[i][j] = in[j][i];
    end
  end
  return transpose;
endfunction

// Convert AES byte state matrix to internal GHASH bit vector representation.
function automatic logic [127:0] aes_state_to_ghash_vec(logic [3:0][3:0][7:0] in);
  logic [127:0] out;
  logic [15:0][7:0] byte_vec;
  for (int i = 0; i < 4; i++) begin
    for (int j = 0; j < 4; j++) begin
      byte_vec[15 - 4*i - j] = in[j][i];
    end
  end
  out = byte_vec;
  return out;
endfunction

// Convert internal GHASH bit vector representation to simple bit vector.
function automatic logic [127:0] aes_ghash_reverse_bit_order(logic [127:0] in);
  logic [127:0] out;
  for (int i = 0; i < 128; i++) begin
    out[i] = in[127-i];
  end
  return out;
endfunction

// Extract single column from state matrix
function automatic logic [3:0][7:0] aes_col_get(logic [3:0][3:0][7:0] in, logic [1:0] idx);
  logic [3:0][7:0] out;
  for (int i = 0; i < 4; i++) begin
    out[i] = in[i][idx];
  end
  return out;
endfunction

// Matrix-vector multiplication in GF(2^8): c = A * b
function automatic logic [7:0] aes_mvm(
  logic [7:0] vec_b,
  logic [7:0] mat_a [8]
);
  logic [7:0] vec_c;
  vec_c = '0;
  for (int i = 0; i < 8; i++) begin
    for (int j = 0; j < 8; j++) begin
      vec_c[i] = vec_c[i] ^ (mat_a[j][i] & vec_b[7-j]);
    end
  end
  return vec_c;
endfunction

// Rotate integer indices
function automatic integer aes_rot_int(integer in, integer num);
  integer out;
  if (in == 0) begin
    out = num - 1;
  end else begin
    out = in - 1;
  end
  return out;
endfunction

// Function for extracting LSBs of the per-S-Box pseudo-random data (PRD) from the output of the
// masking PRNG.
//
// The masking PRNG is used for generating both the PRD for the S-Boxes/SubBytes operation as
// well as for the input data masks. When using any of the masked Canright S-Box implementations,
// it is important that the SubBytes input masks (generated by the PRNG in Round X-1) and the
// SubBytes output masks (generated by the PRNG in Round X) are independent. This can be achieved
// by using e.g. an unrolled Bivium stream cipher primitive inside the PRNG. Since the input data
// masks become the SubBytes input masks in the first round, we select the same 8 bit lanes for the
// input data masks which are also used to form the SubBytes output mask for the masked Canright
// S-Box implementations, i.e., the 8 LSBs of the per S-Box PRD. In particular, we have:
//
// prng_output = { prd_key_expand, ... , sb_prd[4], sb_out_mask[4], sb_prd[0], sb_out_mask[0] }
//
// Where sb_out_mask[x] contains the SubBytes output mask for byte x (when using a masked
// Canright S-Box implementation) and sb_prd[x] contains additional PRD consumed by SubBytes for
// byte x.
//
// When using a masked S-Box implementation other than Canright, we still select the 8 LSBs of
// the per-S-Box PRD to form the input data mask of the corresponding byte. We do this to
// distribute the input data masks over all output bits the masking PRNG.

// For one row of the state matrix, extract the 8 LSBs of the per-S-Box PRD from the PRNG output.
// These bits are used as:
// - input data masks, and
// - SubBytes output mask when using a masked Canright S-Box implementation.
function automatic logic [3:0][7:0] aes_prd_get_lsbs(
  logic [(4*WidthPRDSBox)-1:0] in
);
  logic [3:0][7:0] prd_lsbs;
  for (int i = 0; i < 4; i++) begin
    prd_lsbs[i] = in[i*WidthPRDSBox +: 8];
  end
  return prd_lsbs;
endfunction

endpackage
