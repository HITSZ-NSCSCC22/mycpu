#include "Vtage_predictor.h"
#include <memory>
#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <queue>
#include <deque>

#define BRANCH_LATENCY (5)

// Work around
double sc_time_stamp() { return 0; }

static std::string test_filename = "data/gcc-8M.txt";

struct instruction_entry
{
    uint64_t pc;
    bool taken;
};

// Parse test file
std::vector<instruction_entry> parse_test_file(std::string filename)
{
    std::ifstream test_file(filename);

    if (!test_file.is_open())
    {
        std::cerr << "Open Input File: " << filename << " Failed." << std::endl;
        std::exit(EXIT_FAILURE);
    }

    std::vector<instruction_entry> entries;

    // Read loop
    while (!test_file.eof())
    {
        uint64_t pc;
        char taken_char;
        test_file >> std::hex >> pc;
        test_file >> taken_char;

        entries.push_back({pc, taken_char == 'T'});
    }

    test_file.close();
    return entries;
}

int main(int argc, char const *argv[])
{
    // Enable tracing aka waveform
    const std::unique_ptr<VerilatedContext> context{new VerilatedContext};
    context->debug(0);
    context->traceEverOn(true);
    context->commandArgs(argc, argv);
    Verilated::mkdir("logs");

    // initialize
    std::unique_ptr<Vtage_predictor> sopc(new Vtage_predictor{context.get()});
    sopc->clk = 1;
    sopc->rst = 1;

    // Parse input test file
    auto entries = parse_test_file(test_filename);
    std::cout << "Procceeding with test instructions: " << entries.size() << std::endl;
    std::cout << "First instruction: 0x" << std::hex << entries[0].pc << " " << entries[0].taken << std::dec << std::endl;

    // Delay queue
    std::queue<instruction_entry> delay_queue_taken;
    std::queue<bool> delay_queue_valid;
    for (size_t i = 0; i < BRANCH_LATENCY; i++)
    {
        delay_queue_taken.push({});
        delay_queue_valid.push(false);
    }

    // Reset
    sopc->clk = 0;
    sopc->eval();
    context->timeInc(1);
    sopc->clk = 1;
    sopc->rst = 0;
    sopc->eval();
    context->timeInc(1);

    std::deque<bool> prediction_taken;

    // Simulation loop
    for (size_t i = 0; i < entries.size(); i++)
    {

        sopc->clk = 0;
        sopc->eval();
        context->timeInc(1);

        sopc->pc_i = entries[i].pc;
        sopc->branch_valid_i = delay_queue_valid.front();
        delay_queue_valid.pop();
        sopc->branch_taken_i = delay_queue_taken.front().taken;
        sopc->branch_pc_i = delay_queue_taken.front().pc;
        delay_queue_taken.pop();
        delay_queue_valid.push(true);
        delay_queue_taken.push(entries[i]);

        // Evaluate cycle
        sopc->clk = 1;
        sopc->eval();
        context->timeInc(1);

        // Retrieve prediction
        // std::cout << "predicted, truth: " << (uint32_t)sopc->predict_branch_taken_o << " " << entries[i].taken << std::endl;
        prediction_taken.push_back(sopc->predict_branch_taken_o);
    }
    uint32_t perf_tag_hit_counter[5];
    std::memcpy(perf_tag_hit_counter, sopc->perf_tag_hit_counter, sizeof(uint32_t) * 5);
    std::cout << perf_tag_hit_counter[4] << std::endl;
    std::cout << perf_tag_hit_counter[3] << std::endl;
    std::cout << perf_tag_hit_counter[2] << std::endl;
    std::cout << perf_tag_hit_counter[1] << std::endl;
    std::cout << perf_tag_hit_counter[0] << std::endl;
    sopc->final();

    // First predicto is invalid
    prediction_taken.pop_front();

    // Statistics
    uint64_t correct = 0;
    uint64_t target_taken = 0;
    uint64_t predicted_taken = 0;
    for (size_t i = 0; i < prediction_taken.size(); i++)
    {
        if (entries[i].taken == prediction_taken[i])
        {
            correct++;
        }
        if (entries[i].taken)
        {
            target_taken++;
        }
        if (prediction_taken[i])
        {
            predicted_taken++;
        }
    }
    std::cout << "Correct Taken: " << target_taken << '\n';
    std::cout << "Predicted Taken: " << predicted_taken << '\n';
    std::cout << "Correct: " << correct << '\n';
    std::cout << "Wrong: " << prediction_taken.size() - correct << '\n';
    std::cout << "Correct Rate: " << (double)correct / prediction_taken.size() << std::endl;

    return 0;
}