module top(input i, output o, output p);
  wire n;
  CORE_BUF u_core(.A(i), .Y(n));
  IO_BUF u_io(.A(n), .Y(o));
  NATIVE_BUF u_native(.A(i), .Y(p));
endmodule
