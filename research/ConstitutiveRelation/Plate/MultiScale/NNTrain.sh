#!/bin/bash
 
julia NN_Train_NNPlatePull.jl 1 & 
julia NN_Train_NNPlatePull.jl 2 &

wait
