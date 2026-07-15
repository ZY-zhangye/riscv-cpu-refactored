#include <iostream>
#include <string>

extern "C" void tb_wait_for_enter() {
    std::cout << "[PAUSE] SEG or LED changed. Press Enter to continue..."
              << std::flush;
    std::string line;
    std::getline(std::cin, line);
}
