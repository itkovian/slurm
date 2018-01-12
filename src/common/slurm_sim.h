#ifndef _SLURM_SIM_H
#define _SLURM_SIM_H

#ifdef SLURM_SIMULATOR

#define SLURM_SIM_SHM "/tester_slurm_sim.shm"

/* Offsets */
#define SIM_SECONDS_OFFSET           0
#define SIM_MICROSECONDS_OFFSET      4
#define SIM_GLOBAL_SYNC_FLAG_OFFSET 16
#define SIM_PTHREAD_SLURMCTL_PID     8 
#define SIM_PTHREAD_SLURMD_PID      12
#define SIM_TRACE_RECS_END_SIM_OFFSET 20

void         * timemgr_data;
unsigned int * current_sim;
unsigned int * current_micro;
int          * slurmctl_pid;
int          * slurmd_pid;
char         * global_sync_flag;
int          * trace_recs_end_sim;

extern char           SEM_NAME[];
extern sem_t*         mutexserver;

//extern int total_log_jobs; /* ANA: global variable shared between sim_mgr and controller to help end simulation when all jobs have finished */ 
//extern bool terminate_simulation_from_ctr; /* ANA: it will be read by sim_mgr in order to terminate simulation when all jobs have finished. */

#endif
#endif
