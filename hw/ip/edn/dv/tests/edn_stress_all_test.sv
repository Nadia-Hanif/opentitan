// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class edn_stress_all_test extends edn_base_test;

  `uvm_component_utils(edn_stress_all_test)
  `uvm_component_new

  function void configure_env();
    super.configure_env();

    `DV_CHECK_RANDOMIZE_FATAL(cfg)
    `uvm_info(`gfn, $sformatf("%s", cfg.convert2string()), UVM_LOW)
  endfunction
endclass : edn_stress_all_test
