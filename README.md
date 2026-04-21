vlog -lint rtl/cpu_top/*.sv rtl/cpu_top/*.svh test/*.sv

vsim -voptargs=+acc tb_cpu_top 