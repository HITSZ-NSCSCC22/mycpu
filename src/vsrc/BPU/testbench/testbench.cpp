#include "Vtage_predictor.h"
#include <memory>
#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <queue>
#include <deque>

#include "struct.hpp"

#define BRANCH_LATENCY (3)

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

        entries.push_back({pc, taken_char == 'T' || taken_char == '1'});
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
    std::string input_filename;
    if (argc > 1)
    {
        input_filename = std::string(argv[1]);
    }
    else
    {
        input_filename = test_filename;
    }
    auto entries = parse_test_file(input_filename);
    std::cout << "Procceeding with test instructions: " << entries.size() << std::endl;
    std::cout << "First instruction: 0x" << std::hex << entries[0].pc << " " << entries[0].taken << std::dec << std::endl;
    std::cout << "Size of output meta: " << sizeof(bpu_ftq_meta_t) << std::endl;

    // Reset
    sopc->clk = 0;
    sopc->eval();
    context->timeInc(1);
    sopc->clk = 1;
    sopc->rst = 0;
    sopc->eval();
    context->timeInc(1);

    // Store output meta
    std::deque<bpu_ftq_meta_t> output_meta_queue;

    std::deque<bool> prediction_taken;

    // Simulation loop
    for (size_t i = 0; i < entries.size(); i++)
    {

        sopc->clk = 0;
        sopc->eval();
        context->timeInc(1);

        sopc->pc_i = entries[i].pc;

        sopc->clk = 1;
        sopc->eval();
        context->timeInc(1);

        sopc->clk = 0;
        sopc->eval();
        context->timeInc(1);
        sopc->clk = 1;
        sopc->eval();
        context->timeInc(1);

        // Retrieve prediction after 1 cycle
        // std::cout << "predicted, truth: " << (uint32_t)sopc->predict_branch_taken_o << " " << entries[i].taken << std::endl;
        prediction_taken.push_back(sopc->predict_branch_taken_o);
        // Store meta
        bpu_ftq_meta_t bpu_meta_o;
        std::memcpy(&bpu_meta_o, sopc->bpu_meta_o, sizeof(bpu_meta_o));
        output_meta_queue.push_back(bpu_meta_o);

        // More few cycles to simulate FTQ full
        for (size_t j = 0; j < 4; j++)
        {
            sopc->clk = 1 - sopc->clk;
            sopc->eval();
            context->timeInc(1);
        }

        sopc->clk = 0;
        sopc->eval();
        context->timeInc(1);

        // Provider update info
        size_t update_id = i > BRANCH_LATENCY ? i - BRANCH_LATENCY : 0;
        sopc->update_pc_i = entries[update_id].pc;
        tage_predictor_update_info_t update_info_i;
        std::memcpy(&update_info_i, &output_meta_queue[update_id], (TAGE_META_BITS_SIZE / 8) + 1);
        update_info_i.valid = 1;
        update_info_i.predict_correct = prediction_taken[update_id] == entries[update_id].taken;
        update_info_i.branch_taken = entries[update_id].taken;
        update_info_i.is_conditional = 1;
        std::memcpy(sopc->update_info_i, &update_info_i, sizeof(update_info_i));

        sopc->clk = 1;
        sopc->eval();
        context->timeInc(1);
        sopc->clk = 0;
        sopc->eval();
        context->timeInc(1);
        update_info_i.valid = 0;
        std::memcpy(sopc->update_info_i, &update_info_i, sizeof(update_info_i));
        sopc->clk = 1;
        sopc->eval();
        context->timeInc(1);
    }
    uint32_t perf_tag_hit_counter[16];
    std::memcpy(perf_tag_hit_counter, sopc->perf_tag_hit_counter, sizeof(uint32_t) * 16);
    for (size_t i = 0; i < 16; i++)
    {
        std::cout << perf_tag_hit_counter[i] << std::endl;
    }

    sopc->final();

    // First predicto is invalid
    // prediction_taken.pop_front();

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