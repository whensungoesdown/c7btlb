# record all signals for viewwave.sh
add wave -recursive -depth 10 *

# the testbench ends with $finish
run -all

quit -f
