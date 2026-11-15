// Testbench for VE (rtl/3DO/VE.sv) outputs in reset.
// The framework's video capture keeps running while the core is in reset and
// takes every clock with DCLK high as a dot. The real VE is reset at each of
// the four phases of its dot clock divider (so also while DCLK is high), in
// NTSC and PAL. In reset DCLK must stay low and HBLK_N/VBLK_N show blanking,
// After reset a whole frame must have the active window,
// 640 dots by 240 lines, with one dot clock in every 4 VCLK.
// Run: sim/run_tb.sh tb_ve_reset

`timescale 1ns/1ps

module tb_ve_reset;

	reg         MCLK = 0;
	reg         VCLK = 0;
	reg         RST_N = 0;
	reg         PAL = 0;

	wire [23:0] RGB;
	wire        HS_N, VS_N, HBLK_N, VBLK_N, DCLK;

	integer errors = 0;
	integer checks = 0;

	always #5 MCLK = ~MCLK;
	always #6.17 VCLK = ~VCLK;

	VE dut
	(
		.MCLK(MCLK),
		.VCLK(VCLK),
		.RST_N(RST_N),
		.EN(1'b1),

		.PAL(PAL),

		.VCE(1'b0),
		.AD(24'd0),
		.DE(1'b0),
		.HSYNC_N(),
		.VSYNC_N(),

		.RGB(RGB),
		.HS_N(HS_N),
		.VS_N(VS_N),
		.HBLK_N(HBLK_N),
		.VBLK_N(VBLK_N),
		.DCLK(DCLK),

		.DBG_EXT(8'hFF),
		.DBG_BORD_DIS(1'b1),
		.DBG_HS_START(),
		.DBG_HS_END()
	);

	// in reset, from the third VCLK on (VE synchronises the reset with 2 flops)
	task automatic check_in_reset(input integer phase, input [255:0] name);
		integer i, dclk_high, not_blank;
		begin
			dclk_high = 0;
			not_blank = 0;
			repeat (3) @(posedge VCLK);
			for (i = 0; i < 400; i = i + 1) begin
				@(posedge VCLK);
				#1;
				if (DCLK) dclk_high = dclk_high + 1;
				if (HBLK_N || VBLK_N) not_blank = not_blank + 1;
			end
			checks = checks + 1;
			if (dclk_high != 0 || not_blank != 0) begin
				errors = errors + 1;
				$display("FAIL %0s pal=%0d phase %0d: in reset DCLK high %0d of 400 clocks, not blanking %0d", name, PAL, phase, dclk_high, not_blank);
			end
		end
	endtask

	// one whole frame after reset: 240 lines of 640 dots, DCLK 1 in 4 VCLK
	task automatic check_frame(input integer phase);
		integer dots, lines, bad_lines, vclks, dclks;
		reg act;
		begin
			@(negedge VBLK_N);
			@(posedge VBLK_N);
			dots = 0; lines = 0; bad_lines = 0; vclks = 0; dclks = 0; act = 0;
			while (VBLK_N) begin
				@(posedge VCLK);
				#1;
				vclks = vclks + 1;
				if (DCLK) begin
					dclks = dclks + 1;
					if (HBLK_N) begin
						dots = dots + 1;
						act = 1;
					end else if (act) begin
						if (dots != 640) bad_lines = bad_lines + 1;
						lines = lines + 1;
						dots = 0;
						act = 0;
					end
				end
			end
			checks = checks + 1;
			if (lines != 240 || bad_lines != 0) begin
				errors = errors + 1;
				$display("FAIL frame pal=%0d phase %0d: %0d lines, %0d not 640 dots", PAL, phase, lines, bad_lines);
			end
			checks = checks + 1;
			if (dclks * 4 < vclks - 4 || dclks * 4 > vclks + 4) begin
				errors = errors + 1;
				$display("FAIL frame pal=%0d phase %0d: %0d dot clocks in %0d VCLK", PAL, phase, dclks, vclks);
			end
		end
	endtask

	integer pal, ph;
	initial begin
		repeat (20) @(posedge VCLK);
		RST_N = 1;
		for (pal = 0; pal < 2; pal = pal + 1) begin
			PAL = pal[0];
			check_frame(-1);
			for (ph = 0; ph < 4; ph = ph + 1) begin
				// reset in the middle of an active line, at divider phase ph
				// (phase 3 is the clock DCLK is high)
				@(posedge VBLK_N);
				repeat (100) @(posedge HBLK_N);
				repeat (37) @(posedge VCLK);
				while (dut.DCLK_DIV != ph[1:0]) @(posedge VCLK);
				RST_N = 0;
				check_in_reset(ph, "mid line");
				RST_N = 1;
				check_frame(ph);
			end
			$display("pal=%0d done, errors=%0d", pal, errors);
		end
		$display("checks=%0d errors=%0d", checks, errors);
		if (errors == 0) $display("TEST PASSED");
		else $display("TEST FAILED");
		$finish;
	end

	initial begin
		repeat (4) #1000000000;
		$display("TIMEOUT");
		$finish;
	end

endmodule
