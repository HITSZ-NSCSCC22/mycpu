#include "VSimTop.h"
#include <memory>
#include <iostream>

// Work around
double sc_time_stamp() { return 0; }

int main(int argc, char const *argv[])
{
    // Enable tracing aka waveform
    const std::unique_ptr<VerilatedContext> context{new VerilatedContext};
    context->debug(0);
    context->traceEverOn(true);
    context->commandArgs(argc, argv);
    Verilated::mkdir("logs");

    std::unique_ptr<VSimTop> sopc(new VSimTop{context.get()});
    sopc->clock = 1;
    sopc->reset = 1;

    // Simulation loop
    for (size_t i = 0; i < 10000; i++)
    {
        if (i == 10)
        {
            sopc->reset = 0;
        }

        sopc->clock = 1 - sopc->clock;
        sopc->eval();
        context->timeInc(1);
    }
    sopc->final();

    return 0;
}