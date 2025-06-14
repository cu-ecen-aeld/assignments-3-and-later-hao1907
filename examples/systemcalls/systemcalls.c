#include "systemcalls.h"

/**
 * @param cmd the command to execute with system()
 * @return true if the command in @param cmd was executed
 *   successfully using the system() call, false if an error occurred,
 *   either in invocation of the system() call, or if a non-zero return
 *   value was returned by the command issued in @param cmd.
*/
bool do_system(const char *cmd)
{

/*
 * TODO  add your code here
 *  Call the system() function with the command set in the cmd
 *   and return a boolean true if the system() call completed with success
 *   or false() if it returned a failure
*/
    int result = system(cmd);
    //Check error when calling system.
    if(result == -1 ) {
        perror("system() failed ");
        return false;
    }

    return (WEXITSTATUS(result) == 0);
}

/**
* @param count -The numbers of variables passed to the function. The variables are command to execute.
*   followed by arguments to pass to the command
*   Since exec() does not perform path expansion, the command to execute needs
*   to be an absolute path.
* @param ... - A list of 1 or more arguments after the @param count argument.
*   The first is always the full path to the command to execute with execv()
*   The remaining arguments are a list of arguments to pass to the command in execv()
* @return true if the command @param ... with arguments @param arguments were executed successfully
*   using the execv() call, false if an error occurred, either in invocation of the
*   fork, waitpid, or execv() command, or if a non-zero return value was returned
*   by the command issued in @param arguments with the specified arguments.
*/

bool do_exec(int count, ...)
{
    va_list args;
    va_start(args, count);
    char * command[count+1];
    int i;
    for(i=0; i<count; i++)
    {
        command[i] = va_arg(args, char *);
    }
    command[count] = NULL;

/*
 * TODO:
 *   Execute a system command by calling fork, execv(),
 *   and wait instead of system (see LSP page 161).
 *   Use the command[0] as the full path to the command to execute
 *   (first argument to execv), and use the remaining arguments
 *   as second argument to the execv() command.
 *
*/
    pid_t pid = fork();
    if(pid == -1){
        perror("fork() failed");
        va_end(args);
        return false;
    }else if(pid == 0){
        printf("child process \n");
        execv(command[0], command);
        perror("execv() failed");
        va_end(args);
        _exit(EXIT_FAILURE);  //exit child process if execv failure
    }else {  // Parent process
        int status;
        waitpid(pid, &status, 0);  // wait child process complete
        
        va_end(args);  
        
        if(WIFEXITED(status)) {
            return (WEXITSTATUS(status) == 0);  // return true if exit status true
        }
        return false;  // if child process get signal or other errors.
    }
    return true;
}

/**
* @param outputfile - The full path to the file to write with command output.
*   This file will be closed at completion of the function call.
* All other parameters, see do_exec above
*/
bool do_exec_redirect(const char *outputfile, int count, ...)
{
    va_list args;
    va_start(args, count);
    char *command[count+1];  // +1 for NULL terminator
    int i;
    
    // Get all arguments from va_list
    for(i = 0; i < count; i++)
    {
        command[i] = va_arg(args, char *);
    }
    command[count] = NULL;  // NULL terminate the argument array

    pid_t pid = fork();
    
    if(pid == -1) {
        perror("fork() failed");
        va_end(args);
        return false;
    }
    else if(pid == 0) {  // Child process
        // Open the output file
        int fd = open(outputfile, O_WRONLY|O_CREAT|O_TRUNC, S_IRUSR|S_IWUSR);
        if (fd == -1) {
            perror("open() failed");
            va_end(args);
            _exit(EXIT_FAILURE);
        }

        // Redirect stdout to the file
        if (dup2(fd, STDOUT_FILENO) == -1) {
            perror("dup2() failed");
            close(fd);
            va_end(args);
            _exit(EXIT_FAILURE);
        }
        close(fd);  // Close the original file descriptor

        // Execute the command
        execv(command[0], command);
        
        // If we get here, execv failed
        perror("execv() failed");
        va_end(args);
        _exit(EXIT_FAILURE);
    }
    else {  // Parent process
        int status;
        waitpid(pid, &status, 0);  // Wait for child to complete
        
        va_end(args);  // Clean up va_list

        if(WIFEXITED(status)) {
            return (WEXITSTATUS(status) == 0);  // Return true if exit status 0
        }
        return false;  // Return false if child was signaled or other error
    }
}

