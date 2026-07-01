#include "Vcorev_min_soc_hello_tb.h"
#include "verilated.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <string>

namespace {
constexpr int kTimeoutCycles = 20000;
constexpr const char *kExpected = "SAP-VPU hello\n";

void eval_cycle(Vcorev_min_soc_hello_tb *top) {
  top->clk_i = 0;
  top->eval();
  top->clk_i = 1;
  top->eval();
}
}  // namespace

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);

  Vcorev_min_soc_hello_tb top;
  std::string uart;

  top.clk_i = 0;
  top.rst_ni = 0;
  top.fetch_enable_i = 0;
  top.eval();

  for (int i = 0; i < 5; ++i) {
    eval_cycle(&top);
  }

  top.rst_ni = 1;
  top.fetch_enable_i = 1;
  top.eval();

  for (int cycle = 0; cycle < kTimeoutCycles; ++cycle) {
    eval_cycle(&top);

    if (top.uart_tx_valid_o) {
      uart.push_back(static_cast<char>(top.uart_tx_data_o));
      if (uart.size() > std::char_traits<char>::length(kExpected)) {
        std::fprintf(stderr, "Too many UART bytes: %s\n", uart.c_str());
        return EXIT_FAILURE;
      }
      if (uart.back() != kExpected[uart.size() - 1]) {
        std::fprintf(stderr, "UART mismatch at byte %zu: got 0x%02x expected 0x%02x\n",
                     uart.size() - 1,
                     static_cast<unsigned>(static_cast<uint8_t>(uart.back())),
                     static_cast<unsigned>(static_cast<uint8_t>(kExpected[uart.size() - 1])));
        return EXIT_FAILURE;
      }
    }

    if (top.exit_valid_o) {
      if (top.exit_code_o != 1) {
        std::fprintf(stderr, "Exit code mismatch: got 0x%08x\n", top.exit_code_o);
        return EXIT_FAILURE;
      }
      if (uart != kExpected) {
        std::fprintf(stderr, "UART transcript mismatch: %s\n", uart.c_str());
        return EXIT_FAILURE;
      }
      std::printf("UART transcript: %s", uart.c_str());
      std::printf("Exit code: %u\n", top.exit_code_o);
      top.final();
      return EXIT_SUCCESS;
    }
  }

  std::fprintf(stderr, "Timed out waiting for hello exit; UART so far: %s\n", uart.c_str());
  return EXIT_FAILURE;
}
