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

// Reg predictions that will be scheduled on AHB write to mbox_execute
class soc_ifc_reg_delay_job_mbox_csr_mbox_execute_execute extends soc_ifc_reg_delay_job;
    `uvm_object_utils( soc_ifc_reg_delay_job_mbox_csr_mbox_execute_execute )
    mbox_csr_ext rm; /* mbox_csr_rm */
    mbox_fsm_state_e state_nxt;
    uvm_reg_map map;
    virtual task do_job();
        bit skip = 0;
        `uvm_info("SOC_IFC_REG_DELAY_JOB", "Running delayed job for mbox_csr.mbox_execute.execute", UVM_HIGH)
        // Check mbox_unlock before predicting FSM change, since a force unlock
        // has priority over normal flow
        // mbox_unlock only 'activates' on the falling edge of the pulse; if we detect
        // that, bail out of this prediction job
        if (rm.mbox_unlock.unlock.get_mirrored_value()) begin
            uvm_wait_for_nba_region();
            if (!rm.mbox_unlock.unlock.get_mirrored_value()) begin
                skip = 1;
            end
        end
        if (rm.mbox_fn_state_sigs.mbox_error) begin
            skip = 1;
        end
        if (rm.mbox_lock.lock.get_mirrored_value() && !skip) begin
            rm.mbox_status.mbox_fsm_ps.predict(state_nxt, .kind(UVM_PREDICT_READ), .path(UVM_PREDICT), .map(map));
            case (state_nxt) inside
                MBOX_IDLE: begin
                    rm.mbox_status.status.predict(CMD_BUSY, .kind(UVM_PREDICT_READ), .path(UVM_PREDICT), .map(map));
                    rm.mbox_status.soc_has_lock.predict(1'b0, .kind(UVM_PREDICT_READ), .path(UVM_PREDICT), .map(map));
                    `uvm_info("SOC_IFC_REG_DELAY_JOB", $sformatf("post_predict called through map [%p] on mbox_execute results in state transition. Functional state tracker: [%p] mbox_fsm_ps transition [%p]", map.get_name(), rm.mbox_fn_state_sigs, state_nxt), UVM_FULL)
                    if (rm.mbox_lock.is_busy()) begin
                        `uvm_info("SOC_IFC_REG_DELAY_JOB", "Delay job for mbox_execute attempted to clear mbox_lock, but hit access collision! Flagging clear event in reg-model for mbox_lock callback to handle", UVM_LOW)
                        rm.mbox_lock_clr_miss.trigger(null);
                        uvm_wait_for_nba_region();
                        // If the bus transfer is still in progress (it didn't terminate on the same
                        // falling clock edge as when this delay job was run), then just override the 
                        // mirrored value immediately. Clear is_busy to avoid a UVM_WARNING.
                        // This use-case is definitely a hack, but it is necessary to synchronize
                        // the mbox_lock mirror with the design, chronologically.
                        if (rm.mbox_lock.is_busy()) begin
                            rm.mbox_lock.Xset_busyX(0);
                            rm.mbox_lock.lock.predict(0);
                            rm.mbox_fn_state_sigs = '{mbox_idle: 1'b1, default: 1'b0};
                            rm.mbox_lock.Xset_busyX(1);
                        end
                        else begin
                            fork
                                begin
                                    rm.mbox_lock_clr_miss.wait_off();
                                    disable MBOX_CLR_TIMEOUT;
                                end
                                begin: MBOX_CLR_TIMEOUT
                                    // If it takes any amount of time for the pending lock to be cleared, that
                                    // means we've encountered some environment bug (since the accessing i/f
                                    // completed it's transfer, the reg prediction should be instantaneous)
                                    uvm_wait_for_nba_region();
                                    `uvm_error("SOC_IFC_REG_DELAY_JOB", $sformatf("mbox_lock clear activity, originally requested by mbox_execute callback but unserviceable, was scheduled to be completed during mbox_lock callback but took longer than expected to finish!"))
                                end
                            join_any
                        end
                    end
                    else begin
                        rm.mbox_lock.lock.predict(0);
                        rm.mbox_fn_state_sigs = '{mbox_idle: 1'b1, default: 1'b0};
                    end
                end
                MBOX_EXECUTE_SOC: begin
                    rm.mbox_fn_state_sigs = '{soc_receive_stage: 1'b1, default: 1'b0};
                    `uvm_info("SOC_IFC_REG_DELAY_JOB", $sformatf("post_predict called through map [%p] on mbox_execute results in state transition. Functional state tracker: [%p] mbox_fsm_ps transition [%p]", map.get_name(), rm.mbox_fn_state_sigs, state_nxt), UVM_FULL)
                end
                MBOX_EXECUTE_UC: begin
                    rm.mbox_fn_state_sigs = '{uc_receive_stage: 1'b1, default: 1'b0};
                    `uvm_info("SOC_IFC_REG_DELAY_JOB", $sformatf("post_predict called through map [%p] on mbox_execute results in state transition. Functional state tracker: [%p] mbox_fsm_ps transition [%p]", map.get_name(), rm.mbox_fn_state_sigs, state_nxt), UVM_FULL)
                end
                default: begin
                    `uvm_warning("SOC_IFC_REG_DELAY_JOB", $sformatf("post_predict called through map [%p] on mbox_execute results in unexpected state transition. Functional state tracker: [%p] mbox_fsm_ps transition [%p]", map.get_name(), rm.mbox_fn_state_sigs, state_nxt))
                end
            endcase
            `uvm_info("SOC_IFC_REG_DELAY_JOB", $sformatf("post_predict called through map [%p] on mbox_execute finished processing", map.get_name()), UVM_FULL)
        end
        else begin
            `uvm_info("SOC_IFC_REG_DELAY_JOB",
                      $sformatf("Delay job for mbox_execute does not predict any changes due to: mbox_lock mirror [%d] skip [%d] mbox_fsm_ps [%p] mbox_fn_state_sigs [%p]",
                                rm.mbox_lock.lock.get_mirrored_value(),
                                skip, /*rm.mbox_unlock.unlock.get_mirrored_value(),*/
                                rm.mbox_status.mbox_fsm_ps.get_mirrored_value(),
                                rm.mbox_fn_state_sigs),
                      UVM_LOW)
        end
    endtask
endclass

class soc_ifc_reg_cbs_mbox_csr_mbox_execute_execute extends soc_ifc_reg_cbs_mbox_csr;

    `uvm_object_utils(soc_ifc_reg_cbs_mbox_csr_mbox_execute_execute)

    // Function: post_predict
    //
    // Called by the <uvm_reg_field::predict()> method
    // after a successful UVM_PREDICT_READ or UVM_PREDICT_WRITE prediction.
    //
    // ~previous~ is the previous value in the mirror and
    // ~value~ is the latest predicted value. Any change to ~value~ will
    // modify the predicted mirror value.
    //
    virtual function void post_predict(input uvm_reg_field  fld,
                                       input uvm_reg_data_t previous,
                                       inout uvm_reg_data_t value,
                                       input uvm_predict_e  kind,
                                       input uvm_path_e     path,
                                       input uvm_reg_map    map);
        soc_ifc_reg_delay_job_mbox_csr_mbox_execute_execute delay_job;
        soc_ifc_reg_delay_job_mbox_csr_mbox_prot_error      error_job;
        mbox_csr_ext rm; /* mbox_csr_rm */
        uvm_mem mm; /* mbox_mem_rm "mem model" */
        uvm_reg_block rm_top;
        uvm_reg_block blk = fld.get_parent().get_parent(); /* mbox_csr_rm */
        if (!$cast(rm,blk)) `uvm_fatal ("SOC_IFC_REG_CBS", "Failed to get valid class handle")
        rm_top = rm.get_parent();
        mm = rm_top.get_mem_by_name("mbox_mem_rm");
        delay_job = soc_ifc_reg_delay_job_mbox_csr_mbox_execute_execute::type_id::create("delay_job");
        delay_job.rm = rm;
        delay_job.map = map;
        delay_job.set_delay_cycles(0);
        if (map.get_name() == this.AHB_map_name) begin
            case (kind) inside
                UVM_PREDICT_WRITE: begin
                    // Clearing 'execute' - Expect state transition to MBOX_IDLE
                    if (~value & previous) begin
                        if (rm.mbox_data_q.size() != 0 || rm.mbox_resp_q.size() != 0) begin
                            `uvm_warning("SOC_IFC_REG_CBS", $sformatf("Clearing mbox_execute when data queues are not empty! Did the receiver fetch the amount of data it expected to? mbox_data_q.size() [%0d] mbox_resp_q.size() [%0d]", rm.mbox_data_q.size(), rm.mbox_resp_q.size()))
                        end
                        if (!rm.mbox_fn_state_sigs.uc_done_stage) begin
                            `uvm_error("SOC_IFC_REG_CBS", $sformatf("uC is clearing mbox_execute in unexpected mbox FSM state: [%p]", rm.mbox_fn_state_sigs))
                        end
                        `uvm_info("SOC_IFC_REG_CBS", "Write to mbox_execute clears the field and ends a command", UVM_HIGH)
                        rm.mbox_data_q.delete();
                        rm.mbox_resp_q.delete();
                        delay_job.state_nxt = MBOX_IDLE;
                        delay_jobs.push_back(delay_job);
                        `uvm_info("SOC_IFC_REG_CBS", $sformatf("Write to mbox_execute on map [%s] with value [%x] predicts a state change. Delay job is queued to update DUT model.", map.get_name(), value), UVM_HIGH)
                    end
                    // Setting 'execute' - Expect state transition to MBOX_EXECUTE_SOC
                    else if (value & !previous) begin
                        // Maximum allowable size for data transferred via mailbox
                        int unsigned dlen_cap_dw = (mbox_dlen_mirrored(rm) < (mm.get_size() * mm.get_n_bytes())) ? mbox_dlen_mirrored_dword_ceil(rm) :
                                                                                                                   (mm.get_size() * mm.get_n_bytes()) >> ($clog2(CPTRA_MBOX_DATA_W/8));
                        if (!rm.mbox_fn_state_sigs.uc_data_stage)
                            `uvm_error("SOC_IFC_REG_CBS", $sformatf("mbox_execute is set by uC when in an unexpected state [%p]!", rm.mbox_fn_state_sigs))
                        // Round dlen up to nearest dword boundary and compare with data queue size
                        // On transfer of control, remove extraneous entries from data_q since
                        // reads of these values will be gated for the receiver in DUT
                        if ((rm.mbox_data_q.size()) != mbox_dlen_mirrored_dword_ceil(rm)) begin
                            `uvm_info("SOC_IFC_REG_CBS", $sformatf("Write to mbox_execute initiates mailbox command, but the data queue entry count [%0d dwords] does not match the value of dlen [%0d bytes]!", rm.mbox_data_q.size(), mbox_dlen_mirrored(rm)), UVM_LOW)
                        end
                        if (rm.mbox_data_q.size > dlen_cap_dw) begin
                            `uvm_info("SOC_IFC_REG_CBS", $sformatf("Extra entries detected in mbox_data_q on control transfer - deleting %d entries", rm.mbox_data_q.size() - dlen_cap_dw), UVM_LOW)
                            while (rm.mbox_data_q.size > dlen_cap_dw) begin
                                // Continuously remove last entry until size is equal to dlen, since entries are added with push_back
                                rm.mbox_data_q.delete(rm.mbox_data_q.size()-1);
                            end
                        end
                        else if (rm.mbox_data_q.size < dlen_cap_dw) begin
                            uvm_reg_data_t zeros [$];
                            `uvm_info("SOC_IFC_REG_CBS", $sformatf("Insufficient entries detected in mbox_data_q on control transfer - 0-filling %d entries", dlen_cap_dw - rm.mbox_data_q.size()), UVM_LOW)
                            zeros = '{CPTRA_MBOX_DEPTH{32'h0}};
                            zeros = zeros[0:dlen_cap_dw - rm.mbox_data_q.size() - 1];
                            rm.mbox_data_q = {rm.mbox_data_q, zeros};
                        end
                        `uvm_info("SOC_IFC_REG_CBS", "Write to mbox_execute sets the field and initiates a command", UVM_HIGH)
                        delay_job.state_nxt = MBOX_EXECUTE_SOC;
                        delay_jobs.push_back(delay_job);
                        `uvm_info("SOC_IFC_REG_CBS", $sformatf("Write to mbox_execute on map [%s] with value [%x] predicts a state change. Delay job is queued to update DUT model.", map.get_name(), value), UVM_HIGH)
                    end
                    else begin
                        `uvm_info("SOC_IFC_REG_CBS", $sformatf("post_predict called with kind [%p] has no effect", kind), UVM_FULL)
                    end
                end
                default: begin
                    `uvm_info("SOC_IFC_REG_CBS", $sformatf("post_predict called with kind [%p] has no effect", kind), UVM_FULL)
                end
            endcase
        end
        else if (map.get_name() == this.AXI_map_name) begin
            case (kind) inside
                UVM_PREDICT_WRITE: begin
                    // Check for protocol violations
                    error_job = soc_ifc_reg_delay_job_mbox_csr_mbox_prot_error::type_id::create("error_job");
                    if (rm.mbox_fn_state_sigs.mbox_idle) begin
                        error_job.rm = rm;
                        error_job.map = map;
                        error_job.fld = fld;
                        error_job.set_delay_cycles(0);
                        error_job.state_nxt = MBOX_IDLE;
                        error_job.error = '{axs_without_lock: 1'b1, default: 1'b0};
                        `uvm_info("SOC_IFC_REG_CBS", $sformatf("EXECUTE written during unexpected mailbox state [%p]!", rm.mbox_fn_state_sigs), UVM_LOW)
                    end
                    else if (rm.mbox_fn_state_sigs.mbox_error) begin
                        `uvm_info("SOC_IFC_REG_CBS", $sformatf("Write to %s on map [%s] with value [%x] during mailbox state [%p] has no additional side effects!", fld.get_name(), map.get_name(), value, rm.mbox_fn_state_sigs), UVM_LOW)
                    end
                    else if (!rm.mbox_fn_state_sigs.soc_done_stage &&
                             !(rm.mbox_fn_state_sigs.soc_data_stage /*&& mbox_fsm_state_e'(rm.mbox_status.mbox_fsm_ps.get_mirrored_value()) == MBOX_RDY_FOR_DATA*/)) begin
                        error_job.rm = rm;
                        error_job.map = map;
                        error_job.fld = fld;
                        error_job.set_delay_cycles(0);
                        error_job.state_nxt = MBOX_ERROR;
                        error_job.error = '{axs_incorrect_order: 1'b1, default: 1'b0};
                        `uvm_info("SOC_IFC_REG_CBS", $sformatf("EXECUTE written during unexpected mailbox state [%p]! FSM mirror: [%p]", rm.mbox_fn_state_sigs, rm.mbox_status.mbox_fsm_ps.get_mirrored_value()), UVM_LOW)
                        rm.mbox_fn_state_sigs = '{mbox_error: 1'b1, default: 1'b0};
                    end

                    // Clearing 'execute' - Expect sts pin change
                    if (~value & previous) begin
                        if (rm.mbox_data_q.size() != 0 || rm.mbox_resp_q.size() != 0) begin
                            `uvm_info("SOC_IFC_REG_CBS", $sformatf("Clearing mbox_execute when data queues are not empty! Did the receiver fetch the amount of data it expected to? mbox_data_q.size() [%0d] mbox_resp_q.size() [%0d]", rm.mbox_data_q.size(), rm.mbox_resp_q.size()), UVM_LOW)
                        end
                        if (!rm.mbox_fn_state_sigs.soc_done_stage) begin
                            `uvm_info("SOC_IFC_REG_CBS", $sformatf("mbox_execute is cleared by SOC in unexpected mbox FSM state: [%p]", rm.mbox_fn_state_sigs), UVM_LOW)
                        end
                        `uvm_info("SOC_IFC_REG_CBS", $sformatf("Write to mbox_execute clears the field and ends a command"), UVM_HIGH)
                        rm.mbox_data_q.delete();
                        rm.mbox_resp_q.delete();
                        delay_job.state_nxt = MBOX_IDLE;
                        delay_jobs.push_back(delay_job);
                        `uvm_info("SOC_IFC_REG_CBS", $sformatf("Write to mbox_execute on map [%s] with value [%x] predicts a state change. Delay job is queued to update DUT model.", map.get_name(), value), UVM_HIGH)
                    end
                    // Setting 'execute' - Expect a uC interrupt if enabled
                    else if (value & !previous) begin
                        // Maximum allowable size for data transferred via mailbox
                        int unsigned dlen_cap_dw = (mbox_dlen_mirrored(rm) < (mm.get_size() * mm.get_n_bytes())) ? mbox_dlen_mirrored_dword_ceil(rm) :
                                                                                                                   (mm.get_size() * mm.get_n_bytes()) >> ($clog2(CPTRA_MBOX_DATA_W/8));
                        if (!rm.mbox_fn_state_sigs.soc_data_stage)
                            `uvm_info("SOC_IFC_REG_CBS", $sformatf("mbox_execute is set by SOC when in an unexpected state [%p]!", rm.mbox_fn_state_sigs), UVM_LOW)
                        // Round dlen up to nearest dword boundary and compare with data queue size
                        // On transfer of control, remove extraneous entries from data_q since
                        // reads of these values will be gated for the receiver in DUT
                        if (rm.mbox_data_q.size() != mbox_dlen_mirrored_dword_ceil(rm)) begin
                            `uvm_info("SOC_IFC_REG_CBS", $sformatf("Write to mbox_execute initiates mailbox command, but the data queue entry count [%0d dwords] does not match the value of dlen [%0d bytes]!", rm.mbox_data_q.size(), mbox_dlen_mirrored(rm)), UVM_LOW)
                        end
                        if (rm.mbox_data_q.size > dlen_cap_dw) begin
                            `uvm_info("SOC_IFC_REG_CBS", $sformatf("Extra entries detected in mbox_data_q on control transfer - deleting %d entries", rm.mbox_data_q.size() - dlen_cap_dw), UVM_LOW)
                            while (rm.mbox_data_q.size > dlen_cap_dw) begin
                                // Continuously remove last entry until size is equal to dlen, since entries are added with push_back
                                rm.mbox_data_q.delete(rm.mbox_data_q.size()-1);
                            end
                        end
                        else if (rm.mbox_data_q.size < dlen_cap_dw) begin
                            uvm_reg_data_t zeros [$];
                            `uvm_info("SOC_IFC_REG_CBS", $sformatf("Insufficient entries detected in mbox_data_q on control transfer - 0-filling %d entries", dlen_cap_dw - rm.mbox_data_q.size()), UVM_LOW)
                            zeros = '{CPTRA_MBOX_DEPTH{32'h0}};
                            zeros = zeros[0:dlen_cap_dw - rm.mbox_data_q.size() - 1];
                            rm.mbox_data_q = {rm.mbox_data_q, zeros};
                        end
                        `uvm_info("SOC_IFC_REG_CBS", $sformatf("Write to mbox_execute sets the field and initiates a command"), UVM_HIGH)
                        delay_job.state_nxt = MBOX_EXECUTE_UC;
                        delay_jobs.push_back(delay_job);
                        `uvm_info("SOC_IFC_REG_CBS", $sformatf("Write to mbox_execute on map [%s] with value [%x] predicts a state change. Delay job is queued to update DUT model.", map.get_name(), value), UVM_HIGH)
                    end
                    else begin
                        `uvm_info("SOC_IFC_REG_CBS", $sformatf("post_predict called with kind [%p] has no effect", kind), UVM_FULL)
                    end

                    // Submit error job after delay job so that it executes later and takes precedence
                    if (|error_job.error)
                        delay_jobs.push_back(error_job);
                end
                default: begin
                    `uvm_info("SOC_IFC_REG_CBS", $sformatf("post_predict called with kind [%p] has no effect", kind), UVM_FULL)
                end
            endcase
        end
        else begin
            `uvm_error("SOC_IFC_REG_CBS", "post_predict called through unsupported reg map!")
        end
    endfunction

endclass
