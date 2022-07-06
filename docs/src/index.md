# AlgebraicRL.jl

## Introduction
AlgebraicRL.jl is a library for solving reinforcement learning problems compositionally. Programmatically it relies heavily on ReinforcementLearning.jl, and some understanding of that package is necesarry for using this one. Additionally, this package relies on Catlab.jl and Category Theory, which underpins why compositional reinforcement learning works. **Georgios add some explanation here**.

## How to solve hard RL problems via AlgebraicRL.jl
The basic idea of this package is the following. Assume you have some complicated MDP you cannot solve with traditional RL algorithms. To solve it, do the following steps:
- Break the MDP down into smaller sub-MDPs which are easier to solve
- Solve the sub-MDPs individually
- Using Wiring Diagrams via Catlab.jl, define the order in which the sub-MDPs should be solved in order to solve the overall problem.
- Define how the information, typically internal state, will flow between sub-MDPs. This is done via custom functions, see the documentation on MDPAgentMachine.
- Using the function MDPAgentMachine, create a machine which contains 1 sub-MDP and the policy you have learned to solve it. Create 1 machine per sub-MDP. Use the custom functions from above.
- Place the machines from above into the wiring diagram via oapply. Use eval\_dynamics and read\_output to run the composed machine. This composed machine is running each of the sub-MDPs in the order you gave, and therefore is equilvalent to the original, difficult MDP. Assuming you solved the sub-MDPs, and they represent the harder problem, you have now solved that problem. 
