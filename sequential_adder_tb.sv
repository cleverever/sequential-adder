`timescale 1ns/1ps

`include "uvm_macros.svh"
import uvm_pkg::*;

class transaction #(parameter SIZE = 8) extends uvm_sequence_item;
    rand bit [SIZE-1:0] a;
    rand bit [SIZE-1:0] b;
    bit [SIZE-1:0] sum;
    bit carry;

    function new(string path = "transaction");
        super.new(path);
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

    function new(string path = "generator");
        super.new(path);
    endfunction

    virtual task body();
        t = transaction::type_id::create("t");
        repeat(10) begin
            start_item(t);
            t.randomize();
            `uvm_info("GEN", $sformatf("Data send to driver - a: %d, b: %d", t.a, t.b), UVM_HIGH);
            finish_item(t);
        end
    endtask
endclass

class driver extends uvm_driver #(transaction);
    `uvm_component_utils(driver)

    transaction t;
    virtual add_ifc aifc;

    function new(string path = "driver", uvm_component parent = null);
        super.new(path, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        t = transaction::type_id::create("t");

        if(!uvm_config_db #(virtual aifc)::get(this, "", "aifc", aifc)) begin
            `uvm_error("DRV", "Unable to access uvm_config_db");
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        forever begin
            seq_item_port.get_next_item(t);
            @(posedge aifc.clk);
            `uvm_info("DRV", $sformatf("Starting DUT - a: %d, b: %d", t.a, t.b), UVM_LOW);
            aifc.start <= 1'b1;
            aifc.a <= t.a;
            aifc.b <= t.b;
            @(posedge aifc.clk);
            aifc.start <= 0'b1;
            @(posedge aifc.done);
            seq_item_port.item_done();
        end
    endtask
endclass

class monitor extends uvm_monitor;
    `uvm_component_utils(monitor)

    uvm_analysis_port #(transaction) send;

    transaction t;
    virtual add_ifc aifc;

    function new(string path = "monitor", uvm_component parent = null);
        super.new(path, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        send = new("send", this);
        t = transaction::type_id::create("t");

        if(!uvm_config_db #(virtual aifc)::get(this, "", "aifc", aifc)) begin
            `uvm_error("DRV", "Unable to access uvm_config_db");
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        forever begin
            @(posedge aifc.done);
            t.a <= aifc.a;
            t.b <= aifc.b;
            t.sum <= aifc.sum;
            t.carry <= aifc.carry;
            `uvm_info("monitor", $sformatf("Results sent to scoreboard - a: %d, b: %d, sum: %d, carry: %d", aifc.a, aifc.b, aifc.sum, aifc.carry), UVM_HIGH);
            send.write(t);
        end
    endtask
endclass

class scoreboard extends uvm_scoreboard;
    `uvm_component_utils(scoreboard)

    uvm_analysis_imp #(transaction, scoreboard) recv;

    transaction t;

    function new(string path = "scoreboard", uvm_component parent = null);
        super.new(path, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        recv = new("recv", this);
        t = transaction::type_id::create("t");
    endfunction

    virtual function void write(transaction t);
        this.t = t;
        `uvm_info("scoreboard", $sformatf("Results received - a: %d, b: %d, sum: %d, carry: %d", t.a, t.b, t.sum, t.carry), UVM_LOW);

        if({t.carry, t.sum} == (t.a + t.b)) begin
            `uvm_info("scoreboard", $sformatf("Test Passed"), UVM_NONE);
        end
        else begin
            `uvm_info("scoreboard", $sformatf("Test Failed"), UVM_NONE);
        end
    endfunction
endclass

class agent extends uvm_agent;
    `uvm_component_utils

    monitor m;
    driver d;
    uvm_sequencer #(transaction) seqr;

    function new(string path, uvm_component parent);
        super.new(path, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        m = monitor::type_id::create("m", this);
        d = driver::type_id::create("d", this);
        seqr = uvm_sequencer #(transaction)::type_id::create("seqr", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        d.seq_item_port.connect(seqr.seq_item_export);
    endfunction
endclass

class env extends uvm_env;
    `uvm_component_utils(env)

    scoreboard s;
    agent a;

    function new(string path, uvm_component parent = null);
        super.new(path, parent)
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        s = scoreboard::type_id::create("s", this);
        a = agent::type_id::create("a", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        a.m.send.connect(s.recv);
    endfunction
endclass

class test extends uvm_test;
    `uvm_component_utils

    generator g;
    env e;

    function new(string path = "test", uvm_component parent = null);
        super.new(path, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        g = generator::type_id::create("g");
        e = env::type_id::create("e");
    endfunction

    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        g.start(e.a.seq);
        #50;
        phase.drop_objection(this);
    endtask
endclass

interface add_ifc #(parameter SIZE = 8);
logic clk;
logic start;
logic [SIZE-1:0] a;
logic [SIZE-1:0] b;
logic [SIZE-1:0] sum;
logic carry;
logic done;
endinterface

module sequential_adder_tb;

add_ifc aifc();

sequential_adder DUT
(
    .clk(aifc.clk),
    .start(aifc.start),
    .a(aifc.a),
    .b(aifc.b),
    .sum(aifc.sum),
    .carry(aifc.carry),
    .done(aifc.done),
);

always begin
    aifc.clk <= ~aifc.clk;
end

initial begin
    aifc.clk <= 0;
    aifc.start <= 0;
    uvm_config_db #(virtual add_ifc)::set(null, "*", "aifc", aifc);
    run_test("test");
end

endmodule