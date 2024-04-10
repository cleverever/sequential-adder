`timescale 1ns/1ps

`include "uvm_macros.svh"

import uvm_pkg::*;

interface sequential_adder_ifc;
logic clk;
logic start;
logic [7:0] a;
logic [7:0] b;
logic [7:0] sum;
logic carry;
logic done;
endinterface

class transaction extends uvm_sequence_item;
rand bit [7:0] a;
rand bit [7:0] b;
bit [7:0] sum;
bit carry;

function new(input string inst = "transaction");
  super.new(inst);
endfunction
 
`uvm_object_utils_begin(transaction)
`uvm_field_int(a, UVM_DEFAULT)
`uvm_field_int(b, UVM_DEFAULT)
`uvm_field_int(sum, UVM_DEFAULT)
`uvm_field_int(carry, UVM_DEFAULT)
`uvm_object_utils_end
endclass

class generator extends uvm_sequence #(transaction);
`uvm_object_utils(generator)

transaction t;
 
function new(input string inst = "GEN");
  super.new(inst);
endfunction
 
virtual task body();
  t = transaction::type_id::create("t");
  repeat(10) begin
    start_item(t);
    t.randomize();
    finish_item(t);
    `uvm_info("GEN",$sformatf("Data send to Driver a: %0d, b: %0d",t.a,t.b), UVM_HIGH);  
  end
endtask
endclass

class driver extends uvm_driver #(transaction);
`uvm_component_utils(driver)

transaction data;
virtual sequential_adder_ifc sa_ifc;

function new(input string inst = "DRV", uvm_component parent = null);
  super.new(inst, parent);
endfunction

virtual function void build_phase(uvm_phase phase);
  super.build_phase(phase);
  data = transaction::type_id::create("data");
  if(!uvm_config_db #(virtual sequential_adder_ifc)::get(this,"","sa_ifc",sa_ifc)) begin
    `uvm_error("DRV","Unable to access uvm_config_db");
  end
endfunction

virtual task run_phase(uvm_phase phase);
  forever begin
    seq_item_port.get_next_item(data);
    `uvm_info("DRV", "Waiting for clk posedge to raise start and send operands", UVM_DEBUG);
    @(posedge sa_ifc.clk);
    sa_ifc.start <= 1'b1;
    sa_ifc.a <= data.a;
    sa_ifc.b <= data.b;
    `uvm_info("DRV", $sformatf("Stimulus sent to DUT a: %0d, b: %0d",data.a, data.b), UVM_LOW);
    `uvm_info("DRV", "Waiting for next clk posedge to lower start", UVM_DEBUG);
    @(posedge sa_ifc.clk);
    sa_ifc.start <= 1'b0;
    `uvm_info("DRV", "Waiting for done signal", UVM_DEBUG);
    @(posedge sa_ifc.done);
    seq_item_port.item_done();
  end
endtask
endclass

class monitor extends uvm_monitor;
`uvm_component_utils(monitor)

uvm_analysis_port #(transaction) send;
transaction t;
virtual sequential_adder_ifc sa_ifc;

function new(input string inst = "MON", uvm_component parent = null);
  super.new(inst, parent);
endfunction

virtual function void build_phase(uvm_phase phase);
  super.build_phase(phase);
  t = transaction::type_id::create("TRANS");
  send = new("Write", this);
  if(!uvm_config_db #(virtual sequential_adder_ifc)::get(this,"","sa_ifc",sa_ifc)) begin
    `uvm_error("MON","Unable to access uvm_config_db");
  end
endfunction

virtual task run_phase(uvm_phase phase);
  forever begin
    @(posedge sa_ifc.done);
    t.a = sa_ifc.a;
    t.b = sa_ifc.b;
    t.sum = sa_ifc.sum;
    t.carry = sa_ifc.carry;
    `uvm_info("MON", $sformatf("Data send to Scoreboard a: %0d, b: %0d, sum: %0d carry: %0d", t.a,t.b,t.sum,t.carry), UVM_HIGH);
    send.write(t);
  end
endtask
endclass

class scoreboard extends uvm_scoreboard;
`uvm_component_utils(scoreboard)

uvm_analysis_imp #(transaction,scoreboard) recv;
transaction data;

function new(input string inst = "SCO", uvm_component parent = null);
  super.new(inst, parent);
endfunction

virtual function void build_phase(uvm_phase phase);
  super.build_phase(phase);
  data = transaction::type_id::create("TRANS");
  recv = new("Read", this);
endfunction

virtual function void write(input transaction t);
  data = t;
  `uvm_info("SCO",$sformatf("Data received from Monitor a: %0d, b: %0d, sum: %0d, carry: %0d, sum with carry: %0d",t.a,t.b,t.sum,t.carry,{t.carry, t.sum}), UVM_LOW);
  if({data.carry, data.sum} == data.a + data.b) begin
    `uvm_info("SCO","Test Passed", UVM_NONE)
  end
  else begin
    `uvm_info("SCO","Test Failed", UVM_NONE);
  end
endfunction
endclass

class agent extends uvm_agent;
`uvm_component_utils(agent)

monitor m;
driver d;
uvm_sequencer #(transaction) seq;

function new(input string inst = "AGENT", uvm_component parent = null);
  super.new(inst, parent);
endfunction

virtual function void build_phase(uvm_phase phase);
  super.build_phase(phase);
  m = monitor::type_id::create("MON",this);
  d = driver::type_id::create("DRV",this);
  seq = uvm_sequencer #(transaction)::type_id::create("SEQ",this);
endfunction

virtual function void connect_phase(uvm_phase phase);
  super.connect_phase(phase);
  d.seq_item_port.connect(seq.seq_item_export);
endfunction
endclass

class env extends uvm_env;
`uvm_component_utils(env)

scoreboard s;
agent a;

function new(input string inst = "ENV", uvm_component parent = null);
  super.new(inst, parent);
endfunction

virtual function void build_phase(uvm_phase phase);
  super.build_phase(phase);
  s = scoreboard::type_id::create("SCO",this);
  a = agent::type_id::create("AGENT",this);
endfunction

virtual function void connect_phase(uvm_phase phase);
  super.connect_phase(phase);
  a.m.send.connect(s.recv);
endfunction
endclass

class test extends uvm_test;
`uvm_component_utils(test)

generator gen;
env e;

function new(input string inst = "TEST", uvm_component parent = null);
  super.new(inst, parent);
endfunction

virtual function void build_phase(uvm_phase phase);
  super.build_phase(phase);
  gen = generator::type_id::create("GEN",this);
  e = env::type_id::create("ENV",this);
endfunction

virtual task run_phase(uvm_phase phase);
  phase.raise_objection(this);
  gen.start(e.a.seq);
  phase.drop_objection(this);
endtask
endclass

module sequential_adder_tb();
sequential_adder_ifc sa_ifc();

always begin
  sa_ifc.clk = ~sa_ifc.clk;
  #10ns;
end

sequential_adder DUT
(
  .clk(sa_ifc.clk),
  .start(sa_ifc.start),
  .a(sa_ifc.a),
  .b(sa_ifc.b),
  .sum(sa_ifc.sum),
  .carry(sa_ifc.carry),
  .done(sa_ifc.done)
);
  
initial begin
  sa_ifc.clk = 0;
  uvm_config_db #(virtual sequential_adder_ifc)::set(null, "*", "sa_ifc", sa_ifc);
  run_test("test");
end
endmodule