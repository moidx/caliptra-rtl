//----------------------------------------------------------------------
// Created with uvmf_gen version 2022.3
//----------------------------------------------------------------------
// SPDX-License-Identifier: Apache-2.0
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

//----------------------------------------------------------------------
//----------------------------------------------------------------------
//
// DESCRIPTION: Mailbox/Multi-Agent sequence provides a command flow
//              that attempts to execute a mailbox command from multiple
//              requestors (using a different, legal AxUSER).
//              This is facilitated by running the mailbox flow
//              in a fork with a randomized delay before the sequence entry,
//              to vary which agent successfully wins the access.
//              After the first winning mailbox flow completes, system should
//              be at idle operational capability (which means the next mailbox
//              flow will finally run).
//              Expected result:
//               - All expected mailbox flows attempt to gain lock
//               - First flow (having smallest startup delay) wins first lock
//               - Each subsequent mailbox flow is stalled until previous
//                 flow completes, and then is able to execute.
//               - No two flows proceed past mbox_acquire_lock at the same time
//               - All expected mailbox flows complete
//
//----------------------------------------------------------------------
//----------------------------------------------------------------------
//
class soc_ifc_env_mbox_rand_multi_agent_sequence extends soc_ifc_env_sequence_base #(.CONFIG_T(soc_ifc_env_configuration_t));


  `uvm_object_utils( soc_ifc_env_mbox_rand_multi_agent_sequence )

  rand int agents;
  bit [aaxi_pkg::AAXI_AWUSER_WIDTH-1:0] mbox_valid_users [6];
  bit [aaxi_pkg::AAXI_AWUSER_WIDTH-1:0] mbox_valid_users_uniq [$];
  soc_ifc_env_mbox_sequence_base_t      soc_ifc_env_mbox_multi_agent_seq[];

  // Max agents is equal to number of supported AxUSER values
  constraint agents_c { agents inside {[1:6]}; }

  extern virtual function      create_seqs();
  extern virtual function      randomize_seqs();
  extern virtual task          start_seqs();

  function new(string name = "" );
    super.new(name);
  endfunction

  virtual task pre_body();
    super.pre_body();
    reg_model = configuration.soc_ifc_rm;

    // Check responder handle
    if (soc_ifc_status_agent_rsp_seq == null) begin
        `uvm_fatal("SOC_IFC_MBOX", "SOC_IFC ENV mailbox sequence expected a handle to the soc_ifc status agent responder sequence (from bench-level sequence) but got null!")
    end

    // Find unique configured valid_users (AxUSER) in mailbox and use this to
    // cull agent count
    foreach(reg_model.soc_ifc_reg_rm.CPTRA_MBOX_AXI_USER_LOCK[ii]) begin: VALID_USER_LOOP
        if (reg_model.soc_ifc_reg_rm.CPTRA_MBOX_AXI_USER_LOCK[ii].LOCK.get_mirrored_value())
            mbox_valid_users[ii] = reg_model.soc_ifc_reg_rm.CPTRA_MBOX_VALID_AXI_USER[ii].get_mirrored_value();
        else
            mbox_valid_users[ii] = reg_model.soc_ifc_reg_rm.CPTRA_MBOX_VALID_AXI_USER[ii].get_reset("HARD");
    end
    mbox_valid_users[5] = '1; // FIXME hardcoded to reflect default AxUSER valid value
    mbox_valid_users.shuffle;
    mbox_valid_users_uniq = mbox_valid_users.unique;
    `uvm_info("SOC_IFC_MBOX", $sformatf("Unique mbox_valid_users found: %p", mbox_valid_users_uniq), UVM_MEDIUM) // FIXME increase verbosity
    // Each agent must have a unique AxUSER.
    // If insufficient AxUSER values have been setup, limit number of parallel
    // sequences.
    if (mbox_valid_users_uniq.size() < agents) begin
        agents = mbox_valid_users_uniq.size();
        `uvm_info("SOC_IFC_MBOX", $sformatf("Found %d unique valid AxUSER values initialized. Restricting parallel agent count to %d", mbox_valid_users_uniq.size(), agents), UVM_MEDIUM)
    end
  endtask

  virtual task body();

    int ii;
    int sts_rsp_count = 0;
    uvm_status_e sts;

    // Create the sequence array after randomize call has completed
    create_seqs();

    // Response sequences catch 'status' transactions
    for (ii=0; ii<agents; ii++) begin
        soc_ifc_env_mbox_multi_agent_seq[ii].soc_ifc_status_agent_rsp_seq = soc_ifc_status_agent_rsp_seq;
    end

    fork
        forever begin
            @(soc_ifc_status_agent_rsp_seq.new_rsp) sts_rsp_count++;
        end
    join_none

    // Initiate the mailbox command sender and receiver sequences
    randomize_seqs();
    start_seqs();

    `uvm_info("SOC_IFC_MBOX", "Mailbox multi-agent sequence done", UVM_LOW)

  endtask

endclass

function soc_ifc_env_mbox_rand_multi_agent_sequence::create_seqs();
    int ii;
    uvm_object obj;
    enum {
        SMALL,
        MEDIUM,
        LARGE,
        OVERFLOW_SMALL,
        OVERFLOW_MEDIUM,
        OVERFLOW_LARGE,
        UNDERFLOW_SMALL,
        UNDERFLOW_MEDIUM,
        UNDERFLOW_LARGE,
        MIN,
        MAX,
        DELAY_SMALL,
        DELAY_MEDIUM,
        DELAY_LARGE,
        AXI_USER_SMALL,
        AXI_USER_MEDIUM,
        AXI_USER_LARGE,
        INTERFERENCE_MEDIUM
    } seq_type;

    soc_ifc_env_mbox_multi_agent_seq = new[agents];

    for (ii=0; ii<agents; ii++) begin
        void'(std::randomize(seq_type) with { seq_type dist { SMALL                 := 100,
                                                              MEDIUM                := 50,
                                                              LARGE                 := 1,
                                                              OVERFLOW_SMALL        := 50,
                                                              OVERFLOW_MEDIUM       := 30,
                                                              OVERFLOW_LARGE        := 1,
                                                              UNDERFLOW_SMALL       := 50,
                                                              UNDERFLOW_MEDIUM      := 30,
                                                              UNDERFLOW_LARGE       := 1,
                                                              MIN                   := 50,
                                                              MAX                   := 50,
                                                              DELAY_SMALL           := 100,
                                                              DELAY_MEDIUM          := 50,
                                                              DELAY_LARGE           := 1,
                                                              AXI_USER_SMALL        := 50,
                                                              AXI_USER_MEDIUM       := 20,
                                                              AXI_USER_LARGE        := 1,
                                                              INTERFERENCE_MEDIUM   := 10   }; });
        case (seq_type) inside
            SMALL:
                obj = soc_ifc_env_mbox_rand_small_sequence_t::get_type().create_object($sformatf("soc_ifc_env_mbox_multi_agent_seq[%0d]",ii));
            MEDIUM:
                obj = soc_ifc_env_mbox_rand_medium_sequence_t::get_type().create_object($sformatf("soc_ifc_env_mbox_multi_agent_seq[%0d]",ii));
            LARGE:
                obj = soc_ifc_env_mbox_rand_large_sequence_t::get_type().create_object($sformatf("soc_ifc_env_mbox_multi_agent_seq[%0d]",ii));
            OVERFLOW_SMALL:
                obj = soc_ifc_env_mbox_dlen_overflow_small_sequence_t::get_type().create_object($sformatf("soc_ifc_env_mbox_multi_agent_seq[%0d]",ii));
            OVERFLOW_MEDIUM:
                obj = soc_ifc_env_mbox_dlen_overflow_medium_sequence_t::get_type().create_object($sformatf("soc_ifc_env_mbox_multi_agent_seq[%0d]",ii));
            OVERFLOW_LARGE:
                obj = soc_ifc_env_mbox_dlen_overflow_large_sequence_t::get_type().create_object($sformatf("soc_ifc_env_mbox_multi_agent_seq[%0d]",ii));
            UNDERFLOW_SMALL:
                obj = soc_ifc_env_mbox_dlen_underflow_small_sequence_t::get_type().create_object($sformatf("soc_ifc_env_mbox_multi_agent_seq[%0d]",ii));
            UNDERFLOW_MEDIUM:
                obj = soc_ifc_env_mbox_dlen_underflow_medium_sequence_t::get_type().create_object($sformatf("soc_ifc_env_mbox_multi_agent_seq[%0d]",ii));
            UNDERFLOW_LARGE:
                obj = soc_ifc_env_mbox_dlen_underflow_large_sequence_t::get_type().create_object($sformatf("soc_ifc_env_mbox_multi_agent_seq[%0d]",ii));
            MIN:
                obj = soc_ifc_env_mbox_min_sequence_t::get_type().create_object($sformatf("soc_ifc_env_mbox_multi_agent_seq[%0d]",ii));
            MAX:
                obj = soc_ifc_env_mbox_max_sequence_t::get_type().create_object($sformatf("soc_ifc_env_mbox_multi_agent_seq[%0d]",ii));
            DELAY_SMALL:
                obj = soc_ifc_env_mbox_rand_delay_small_sequence_t::get_type().create_object($sformatf("soc_ifc_env_mbox_multi_agent_seq[%0d]",ii));
            DELAY_MEDIUM:
                obj = soc_ifc_env_mbox_rand_delay_medium_sequence_t::get_type().create_object($sformatf("soc_ifc_env_mbox_multi_agent_seq[%0d]",ii));
            DELAY_LARGE:
                obj = soc_ifc_env_mbox_rand_delay_large_sequence_t::get_type().create_object($sformatf("soc_ifc_env_mbox_multi_agent_seq[%0d]",ii));
            AXI_USER_SMALL:
                obj = soc_ifc_env_mbox_rand_axi_user_small_sequence_t::get_type().create_object($sformatf("soc_ifc_env_mbox_multi_agent_seq[%0d]",ii));
            AXI_USER_MEDIUM:
                obj = soc_ifc_env_mbox_rand_axi_user_medium_sequence_t::get_type().create_object($sformatf("soc_ifc_env_mbox_multi_agent_seq[%0d]",ii));
            AXI_USER_LARGE:
                obj = soc_ifc_env_mbox_rand_axi_user_large_sequence_t::get_type().create_object($sformatf("soc_ifc_env_mbox_multi_agent_seq[%0d]",ii));
            INTERFERENCE_MEDIUM:
                obj = soc_ifc_env_mbox_rand_medium_interference_sequence_t::get_type().create_object($sformatf("soc_ifc_env_mbox_multi_agent_seq[%0d]",ii));
            default:
                `uvm_fatal("SOC_IFC_MBOX", $sformatf("Unrecognized seq_type: %p", seq_type))
        endcase
        if (!$cast(soc_ifc_env_mbox_multi_agent_seq[ii],obj))
            `uvm_fatal("SOC_IFC_MBOX","Failed to create mailbox sequence")
        `uvm_info("SOC_IFC_MBOX", $sformatf("seq_type randomized to: %s", soc_ifc_env_mbox_multi_agent_seq[ii].get_type_name()), UVM_MEDIUM)
    end
endfunction

function soc_ifc_env_mbox_rand_multi_agent_sequence::randomize_seqs();
    int ii;
    for (ii=0; ii<agents; ii++) begin
        if(!soc_ifc_env_mbox_multi_agent_seq[ii].randomize())
            `uvm_fatal("SOC_IFC_MBOX", $sformatf("soc_ifc_env_mbox_rand_multi_agent_sequence::body() - %s randomization failed", soc_ifc_env_mbox_multi_agent_seq[ii].get_type_name()));
        // Each sequence (aka "agent") has a unique AxUSER
        soc_ifc_env_mbox_multi_agent_seq[ii].mbox_user_override_val = mbox_valid_users_uniq.pop_front();
        soc_ifc_env_mbox_multi_agent_seq[ii].override_mbox_user = 1'b1;
    end
endfunction

task soc_ifc_env_mbox_rand_multi_agent_sequence::start_seqs();
    int unsigned delay_clks[]; // Delay prior to running start
    delay_clks = new[agents];

    `uvm_info("SOC_IFC_MBOX", $sformatf("Initiating [%0d] mailbox sequences in parallel", agents), UVM_LOW)
    foreach (soc_ifc_env_mbox_multi_agent_seq[ii]) begin
        if (!std::randomize(delay_clks[ii]) with {delay_clks[ii] < 4*(soc_ifc_env_mbox_multi_agent_seq[ii].mbox_op_rand.dlen+20); delay_clks[ii] > 0;}) begin
            `uvm_fatal("SOC_IFC_MBOX", $sformatf("soc_ifc_env_mbox_rand_multi_agent_sequence::body() - %s randomization failed", "delay_clks"));
        end
        else
            `uvm_info("SOC_IFC_MBOX", $sformatf("soc_ifc_env_mbox_rand_multi_agent_sequence::body() - %s[%0d] randomized to value: %0d", "delay_clks", ii, delay_clks[ii]), UVM_HIGH);
        fork
            automatic int ii_val = ii;
            begin
                configuration.soc_ifc_ctrl_agent_config.wait_for_num_clocks(delay_clks[ii_val]);
                `uvm_info("SOC_IFC_MBOX", $sformatf("Initiating sequence [%0d]/[%0d] in multi-agent flow", ii_val, agents-1), UVM_MEDIUM)
                soc_ifc_env_mbox_multi_agent_seq[ii_val].start(configuration.vsqr);
            end
        join_none
    end
    foreach (soc_ifc_env_mbox_multi_agent_seq[ii])
        soc_ifc_env_mbox_multi_agent_seq[ii].wait_for_sequence_state(STOPPED|FINISHED);

endtask
