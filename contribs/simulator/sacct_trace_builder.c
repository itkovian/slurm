/*
 * trace builder from sacct output.
 * 
 * sacct command:
 * sacct --format=JobID,Account,ReqCPUS,UID,QOS,Partition,Submit,TimeLimit,Start,End,AllocCPUS,AllocNodes -P
 */

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <string.h>
#include <ctype.h>
#include <unistd.h>
#include <getopt.h>
#include <pwd.h>

#define SLURM_SIMULATOR
#include "sim_trace.h"

/* Flag set by ‘--verbose’. */
static int verbose_flag;


void print_usage(){
	printf("\nUsage:\n");
	printf("--> sacct_trace_builder -t trace_file -f <filename> [-h | --help]\n\n");
}

/* https://stackoverflow.com/questions/9210528/split-string-with-delimiters-in-c */
char** str_split(char* a_str, const char a_delim, int* num_fields)
{
    char** result    = 0;
    size_t count     = 0;
    char* tmp        = a_str;
    char* last_comma = 0;
    char delim[2];
    delim[0] = a_delim;
    delim[1] = 0;

    /* Count how many elements will be extracted. */
    while (*tmp)
    {
        if (a_delim == *tmp)
        {
            count++;
            last_comma = tmp;
        }
        tmp++;
    }

    /* Add space for trailing token. */
    count += last_comma < (a_str + strlen(a_str) - 1);

	/* get the number of actual fields */
	*num_fields = count;

    /* Add space for terminating null string so caller
       knows where the list of returned strings ends. */
    count++;

    result = malloc(sizeof(char*) * count);

    if (result)
    {
        size_t idx  = 0;
        char* token = strtok(a_str, delim);

        while (token)
        {
            assert(idx < count);
            *(result + idx++) = strdup(token);
            token = strtok(0, delim);
        }
        assert(idx == count - 1);
        *(result + idx) = 0;
    }

    return result;
}

long convert_to_seconds(char** fields) {

	// We need to check for DD-HH in the first field. Sigh.
	char* tmp = fields[0];
	int days = 0;
	int count = 0;
	while (*(tmp+count)) {
		if (*(tmp+count) == '-') {
			char* d = strndup(tmp, count);
			days = atoi(d);
			free(d);
			tmp = tmp + count + 1;
			break;
		}
		count++;
	}
	return (((days * 24 + atoi(tmp)) * 60) + atoi(fields[1])) * 60 + atoi(fields[2]);
}

int 
main(int argc, char **argv){

	int i,c,written,j;
	FILE* source_file;
	FILE* trace_file;
	char start[20];
	char end[20];
	long int start_timestamp;
	long int stop_timestamp;
	char year[4], month[2], day[2], hours[2], minutes[2], seconds[2];
	
	char *endtime = NULL;
	char *source = "trace";
	char *trace = "slurm.trace";

	job_trace_t new_trace;

	while(1){
		static struct option long_options[] = {
			/* These options don’t set a flag.
			We distinguish them by their indices. */
			{"tracefile",  required_argument, 0, 't'},
			{"sourcefile", required_argument, 0, 'f'},
			{"help",       no_argument,	 0, 'h'},
			{0, 0, 0, 0}
		};

	/* getopt_long stores the option index here. */
	int option_index = 0;
	c = getopt_long (argc, argv, "t:f:h",long_options, &option_index);

	/* Detect the end of the options. */
	if (c == -1)
	break;

	switch (c) {
		case 0:
			/* If this option set a flag, do nothing else now. */
			if (long_options[option_index].flag != 0)
				break;
			printf("option %s", long_options[option_index].name);
			if (optarg)
				printf(" with arg %s", optarg);
			printf("\n");
			break;

		case 't':
			trace = optarg;
			/*printf ("option -t with value `%s'\n", optarg);*/
			break;

		case 'f':
			source = optarg;
			/*printf ("option -f with value `%s'\n", optarg);*/
			break;

		case 'h':
			print_usage();
			exit(0);

		case '?':
			/* getopt_long already printed an error message. */
			break;

		default:
			print_usage();
			abort();
		}
	} //while

	/* Print any remaining command line arguments (not options). */
	if (optind < argc) {
		printf ("non-option ARGV-elements: ");
		while (optind < argc)
		        printf ("%s ", argv[optind++]);
		putchar ('\n');
	}

	//snprintf(query, sizeof(query), "SELECT id_job, account, cpus_req, id_user, partition, time_submit, timelimit, (time_end-time_start) as duration, cpus_alloc, nodes_alloc from %s where FROM_UNIXTIME(time_submit) BETWEEN '%s' AND '%s' AND time_end>0 AND nodes_alloc>0", table, starttime, endtime);

	/* reading resultsd from source */
	if((source_file = fopen(source, "r")) == NULL) {
		printf("Error opening file %s\n", source);
		return -1;
	}

	/*writing results to file*/
	if((trace_file = fopen(trace, "w")) == NULL){
		printf("Error opening file %s\n", trace);
		return -1;
	}

	j = 0;
	size_t linecap = 4096;
	char *line = malloc(linecap);

    if (line == NULL) {
		printf("Cannot allocate buffer space for extracting the line\n");
		return -1;
	}

	while (getline(&line, &linecap, source_file) > -1) {

		int num_fields = 0;
		char **fields = str_split(line, '|', &num_fields);
		int num_timelimit_fields = 0;
		char **timelimit_fields = str_split(fields[7], ':', &num_timelimit_fields);
		for( i = 0; i < num_fields; i++) {
			printf("%s ", fields[i] ? fields[i] : "NULL");
		}
		printf("\n");
		j++;
		
		/* do not take jobs with 0 allocated nodes into account */
		if (atoi(fields[11]) == 0) {
			printf("Not considering job %s with 0 allocated nodes", fields[0]);
			continue;
		}

		/* fields: JobID,Account,ReqCPUS,UID,QOS,Partition,Submit,TimeLimit,Start,End,AllocCPUS,AllocNodes 
		 *         0     1       2       3   4   5         6      7         8     9   10        11
		 */
		new_trace.job_id = atoi(fields[0]);
		new_trace.submit = strtoul(fields[6], NULL, 0);
		sprintf(new_trace.username, "%s", fields[3]);
		sprintf(new_trace.qosname, "%s", fields[4]);
		sprintf(new_trace.partition, "%s", fields[5]);
		sprintf(new_trace.account, "%s", fields[1]);
		new_trace.duration = atol(fields[9]) - atol(fields[8]);
		new_trace.wclimit = convert_to_seconds(timelimit_fields);

		new_trace.cpus_per_task = 1;
		new_trace.tasks_per_node = atoi(fields[10])/atoi(fields[11]);
		new_trace.tasks = atoi(fields[10]);

		sprintf(new_trace.reservation, "%s", "");

		written = fwrite((void*) &new_trace, sizeof(new_trace), 1, trace_file);
		if(written != 1) {
			printf("Error writing to file: %d of %ld\n", written, 1);
			return -1;
		}

		for( i = 0; i < num_fields; i++) {
			free(fields[i]);
		}
		free(fields);
		free(timelimit_fields);

	}

	printf("\nSuccessfully written file %s : Total number of jobs = %d\n", trace, j);

	exit(0);
}
