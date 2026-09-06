///////////////////////////////////////////////////////////////////
// Filename: mixer_env.sv
// Author  : Benjamin Tamayo
// Date    : 09/06/2026
// Purpose : Environment for the video mixer testbench.
//
//           Included into mixer_tb_pkg; not a standalone compilation unit.
///////////////////////////////////////////////////////////////////
//
// Three kinds of agent, because the DUT has three kinds of port:
//   num_layers AXIS master agents, one per layer input, sourcing pixels
//   one AXIS slave agent on the composited output, sourcing TREADY
//   one AXI4-Lite master agent on the control port
//
// The layer agents are built from a loop rather than declared individually so
// that the layer count stays a single number here as well as in the RTL.

class mixer_env extends uvm_env;

  `uvm_component_utils(mixer_env)

  int unsigned num_layers = 4;

  mix_agent_t      layer_agent[MIX_MAX_LAYERS];
  mix_agent_t      out_agent;
  mix_axil_agent_t axil_agent;
  mixer_scoreboard scoreboard;

  axi_stream_config layer_config[MIX_MAX_LAYERS];
  axi_stream_config out_config;
  axi_lite_config   axil_config;

  mix_vif_t      vif_layer[MIX_MAX_LAYERS];
  mix_vif_t      vif_out;
  mix_axil_vif_t vif_axil;

  extern function new(string name = "mixer_env", uvm_component parent = null);
  extern virtual function void build_phase(uvm_phase phase);
  extern virtual function void connect_phase(uvm_phase phase);

endclass : mixer_env


function mixer_env::new(string name = "mixer_env", uvm_component parent = null);
  super.new(name, parent);
endfunction : new


function void mixer_env::build_phase(uvm_phase phase);
  int canvas_w, canvas_h, n_layers;

  super.build_phase(phase);

  if (!uvm_config_db#(int)::get(this, "", "num_layers", n_layers))
    `uvm_fatal("NOCFG", "no 'num_layers' in the config DB")
  num_layers = n_layers;

  if (!uvm_config_db#(int)::get(this, "", "canvas_w", canvas_w))
    `uvm_fatal("NOCFG", "no 'canvas_w' in the config DB")
  if (!uvm_config_db#(int)::get(this, "", "canvas_h", canvas_h))
    `uvm_fatal("NOCFG", "no 'canvas_h' in the config DB")

  // ---- Interfaces published by mixer_tb_top ---------------------------
  if (!uvm_config_db#(mix_vif_t)::get(this, "", "vif_out", vif_out))
    `uvm_fatal("NOVIF", {"no 'vif_out' in the config DB -- check that the type parameters ",
                         "in mixer_tb_top's set() match mix_vif_t exactly"})
  if (!uvm_config_db#(mix_axil_vif_t)::get(this, "", "vif_axil", vif_axil))
    `uvm_fatal("NOVIF", "no 'vif_axil' in the config DB")

  for (int unsigned i = 0; i < num_layers; i++) begin
    string nm = $sformatf("vif_layer%0d", i);
    if (!uvm_config_db#(mix_vif_t)::get(this, "", nm, vif_layer[i]))
      `uvm_fatal("NOVIF", {"no '", nm, "' in the config DB"})
  end

  // ---- Configs built by the test --------------------------------------
  if (!uvm_config_db#(axi_stream_config)::get(this, "", "out_config", out_config))
    `uvm_fatal("NOCFG", "no 'out_config' in the config DB")
  if (!uvm_config_db#(axi_lite_config)::get(this, "", "axil_config", axil_config))
    `uvm_fatal("NOCFG", "no 'axil_config' in the config DB")

  uvm_config_db#(axi_stream_config)::set(this, "out_agent", "agent_config", out_config);
  uvm_config_db#(mix_vif_t)::set(this, "out_agent", "vif", vif_out);
  out_agent = mix_agent_t::type_id::create("out_agent", this);

  uvm_config_db#(axi_lite_config)::set(this, "axil_agent", "agent_config", axil_config);
  uvm_config_db#(mix_axil_vif_t)::set(this, "axil_agent", "vif", vif_axil);
  axil_agent = mix_axil_agent_t::type_id::create("axil_agent", this);

  for (int unsigned i = 0; i < num_layers; i++) begin
    string nm = $sformatf("layer_agent%0d", i);
    string cn = $sformatf("layer_config%0d", i);

    if (!uvm_config_db#(axi_stream_config)::get(this, "", cn, layer_config[i])) begin
      // A test that says nothing about a layer gets a plain full-rate master.
      layer_config[i]            = axi_stream_config::type_id::create(cn);
      layer_config[i].role       = AXIS_MASTER;
      layer_config[i].is_active  = UVM_ACTIVE;
      layer_config[i].has_tuser  = 1'b1;
      layer_config[i].user_width = MIX_USER_WIDTH;
      layer_config[i].has_tlast  = 1'b1;
      layer_config[i].has_tkeep  = 1'b0;
      layer_config[i].has_tstrb  = 1'b0;
    end

    uvm_config_db#(axi_stream_config)::set(this, nm, "agent_config", layer_config[i]);
    uvm_config_db#(mix_vif_t)::set(this, nm, "vif", vif_layer[i]);
    layer_agent[i] = mix_agent_t::type_id::create(nm, this);
  end

  scoreboard            = mixer_scoreboard::type_id::create("scoreboard", this);
  scoreboard.num_layers = num_layers;
  scoreboard.canvas_w   = canvas_w;
  scoreboard.canvas_h   = canvas_h;
endfunction : build_phase


function void mixer_env::connect_phase(uvm_phase phase);
  super.connect_phase(phase);
  // Beat port, not packet port: TUSER carries SOF and the packet class does
  // not compare it.
  out_agent.monitor.beat_analysis_port.connect(scoreboard.analysis_export);
endfunction : connect_phase
