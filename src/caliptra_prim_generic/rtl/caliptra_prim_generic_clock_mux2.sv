// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

`include "caliptra_prim_assert.sv"

module caliptra_prim_generic_clock_mux2 #(
  parameter bit NoFpgaBufG = 1'b0 // this parameter serves no function in the generic model
) (
  input        clk0_i,
  input        clk1_i,
  input        sel_i,
  output logic clk_o
);

  // We model the mux with logic operations for GTECH runs.
  assign clk_o = (sel_i & clk1_i) | (~sel_i & clk0_i);

  // make sure sel is never X (including during reset)
  // need to use ##1 as this could break with inverted clocks that
  // start with a rising edge at the beginning of the simulation.
  `CALIPTRA_ASSERT(selKnown0, ##1 !$isunknown(sel_i), clk0_i, 0)
  `CALIPTRA_ASSERT(selKnown1, ##1 !$isunknown(sel_i), clk1_i, 0)

endmodule : caliptra_prim_generic_clock_mux2
