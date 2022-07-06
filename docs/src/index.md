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


## Algorithm In-depth

Note I am using Capital letters to denote a set and lowercase letters to denote an element.

Assume we have a Markov Decision Process (MDP) we are trying to solve. The MDP is defined by the following: 
- an set of initial states S$_{0}$. We allow the state space to be either discrete or continuous.
- an action space A. We allow the action space to be either discrete or continuous.
- a transition function T(s$_{t}$, a$_{t}$) which returns a distribution of next states S$_{t+1}$ given the state and action taken.
- a reward function R(s$_{t}$, a$_{t}$, s$_{t+1}$) which returns a scalar reward.
- a set of termination states S$_{f}$. Reaching these states causes the MDP to terminate. Note this termination condition could be accomplishing some goal. Alternatively, this could be an empty set for MDPs that do not terminate. 

The goal is to learn a policy π, which is a function that maps from s$_{t}$ to a$_{t}$, that maximizes the total accumulated reward of 1 episode of the MDP given that we apply the action returned by π to the MDP at every timestep.

Suppose that current algorithms for finding the policy π are not succesful. That is, they are not able to find a function mapping from state to action that leads to a high total accumulated reward. Example algorithms, depending on whether the state and action spaces are discrete or continuous, can consists of tabular approaches, DQN, DDPG, PPO, etc. 

Given that this is the case, we must first break the MDP into N sub-MDPs. A sub-MDP is defined to be a MDP, which means its has the same defintion as above. Sub-MDPs however draw many of their elements from the parent MDP:
- an initial set of states S$_{0}$. This set must be a subset of the state space of the parent MDP.
- an action space A. This must be a subset of the action space of the parent MDP.
- a transition function T, which is the same as the transtion function of the parent MDP.
- a reward function R, which can be independent of the parent MDP
- a set of termination states S$_{f}$, which must be a subset of the state space of the parent MDP.

The N sub-MDPs must have the following properties (note I am assuming 1-indexed):
- sub-MDP$_{1}$'s S$_{0}$ must be equal to the S$_{0}$ of the parent MDP
- sub-MDP$_{N}$'s S$_{f}$ must be equal to the S$_{f}$ of the parent MDP
- For all intermediate sub-MDPs, the S$_{f}$ of 1 sub-MDP must be equal to the S$_{0}$ of the following sub-MDP.
In effect, the first sub-MDP is the beginning of the parent MDP. Reaching the termination states of the first sub-MDP is equilvalent to reaching the initial states of the second sub-MDP. In general, the termination states of the i'th sub-MDP are the initial states of the i+1'th sub-MDP. The termination states of the final sub-MDP are the termination states of the parent MDP. 

Therefore, if the human expert has properly dividing the MDP into reasonable sub-MDPs, completing the sub-MDPs sequentially completes the parent MDP. IE completing the first sub-MDP leads to the second. Completing the second leads to the third, and so on, until completing the last sub-MDP leads to the termination states of the parent MDP. 

Since each sub-MDP also meets the definition of an MDP, we can apply any algorithm we choose to find a respective π, such as Tabular approaches, DQN, DDPG, PPO, etc. Therefore, we can learn a sub-policy π$_{i}$ to solve each sub-MDP, and then apply them seqentially to the parent MDP. Thus, the parent MDP can be solved compositionally.

Sub-MDPs have many properties that make them easier to solve than the parent MDP:
- The complexity of the desired behavior can be reduced. Even if the state space and action space are constant, the optimal policy may be much simpler to learn if the behavior of that policy is more general. 
- The state space may be reduced. In some cases, you may need the entire state of the parent MDP to solve the sub-MDP. However, in other cases, only part of the state space is relevant. Any information that is irrelevant can be removed, which makes the problem easier to solve. This is known as information hiding.
- Likewise, the action space may be reduced. In some problems, not all actions are needed to solve a sub-MDP. Removing these actions makes the problem easier to solve as whichever algorithm you choose does not need to explore them. In discrete action spaces, this means removing some actions from the list of actions. In continuous cases, this means setting a predetirmined value for one of the action dimensions. 
- The reward function can be customized for each sub-MDP. This means you can do reward tuning on each sub-MDP individually. This is useful because it is often substantially easier to tune the reward of an easy problem over a complicated one. It is even possible that the parent MDP is so complex it is intractable to create a reward function to encourage the correct behavior. However, it may still be possible to reward tune for sub-MDPs, allowing you to solve a problem that you could not otherwise.

Given the above information, the process can be described as the following:

    function CompositionalRL(MDP):
        Break the MDP into N sub-MDPs
        Find a sub-policy for each sub-MDP
        Combine the sub-policies into 1 policy π by doing the following:
            Determine which sub-MDP is currently active 
            Apply the respective sub-policy
