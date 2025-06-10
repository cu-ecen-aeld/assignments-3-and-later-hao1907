#include "threading.h"
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>

// Optional: use these functions to add debug or error prints to your application
#define DEBUG_LOG(msg,...)
//#define DEBUG_LOG(msg,...) printf("threading: " msg "\n" , ##__VA_ARGS__)
#define ERROR_LOG(msg,...) printf("threading ERROR: " msg "\n" , ##__VA_ARGS__)

void* threadfunc(void* thread_param)
{
    struct thread_data* thread_func_args = (struct thread_data*)thread_param;

    // Chờ wait_to_obtain_ms
    usleep(thread_func_args->wait_to_obtain_ms * 1000); // Chuyển ms sang micro giây

    // Khóa mutex
    if (pthread_mutex_lock(thread_func_args->mutex) != 0) {
        ERROR_LOG("Failed to lock mutex");
        thread_func_args->thread_complete_success = false;
        return thread_param;
    }

    // Chờ wait_to_release_ms
    usleep(thread_func_args->wait_to_release_ms * 1000); // Chuyển ms sang micro giây

    // Mở khóa mutex
    if (pthread_mutex_unlock(thread_func_args->mutex) != 0) {
        ERROR_LOG("Failed to unlock mutex");
        thread_func_args->thread_complete_success = false;
        return thread_param;
    }

    // Đánh dấu thành công
    thread_func_args->thread_complete_success = true;
    return thread_param;
}


bool start_thread_obtaining_mutex(pthread_t *thread, pthread_mutex_t *mutex, int wait_to_obtain_ms, int wait_to_release_ms)
{
    // Cấp phát động thread_data
    struct thread_data* thread_data = (struct thread_data*)malloc(sizeof(struct thread_data));
    if (thread_data == NULL) {
        ERROR_LOG("Failed to allocate memory for thread_data");
        return false;
    }

    // Gán giá trị cho thread_data
    thread_data->mutex = mutex;
    thread_data->wait_to_obtain_ms = wait_to_obtain_ms;
    thread_data->wait_to_release_ms = wait_to_release_ms;
    thread_data->thread_complete_success = false; // Mặc định là false

    // Tạo thread
    if (pthread_create(thread, NULL, threadfunc, thread_data) != 0) {
        ERROR_LOG("Failed to create thread");
        free(thread_data); // Giải phóng nếu thất bại
        return false;
    }

    return true;
}

