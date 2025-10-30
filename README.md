# Мониторинг процесса и API (systemd)

скрипт мониторинга и unit-файлы systemd для запуска раз в минуту.


`test_monit.sh` — проверяет процесс `PS_NAME`, фиксирует рестарт (смену PID), пингует `MONIT_URL`, пишет логи в `LOG`.
`systemd/monitoring.service` — oneshot unit, запускает скрипт.
`systemd/monitoring.timer` — таймер, запускает unit каждую минуту.

## Установка на сервере
1) Пернести файлы
- `sudo cp ./test_monit.sh /usr/local/bin/test_monit.shsudo`
- `chmod 0755 /usr/local/bin/test_monit.shsudoм 
- `cp ./monitoring.service /etc/systemd/system/monitoring.servicesudo`
- `cp ./monitoring.timer /etc/systemd/system/monitoring.timer`

3) Перечитать systemd и запустить таймер
- `sudo systemctl status monitoring.timer`
- `sudo systemctl daemon-reload`
- `sudo systemctl enable --now monitoring.timersudo`
- `systemctl status monitoring.timer`

5) Проверка вручную
- `sudo systemctl start monitoring.servicesudo`
- `systemctl status monitoring.servicesudo`
- `tail -f /var/log/monitoring.log`
Требования: установлен `curl`. 

## Проверка
- Ручной запуск: `sudo systemctl start monitoring.service`
- Логи скрипта: `sudo tail -n 50 /var/log/monitoring.log`
- Журнал unit: `journalctl -u monitoring.service -n 50 --no-pager`
  (сам сервис включать не нужно — его заустит таймер)

## Настройки
- `PS_NAME` — имя процесса
- `MONIT_URL` — URL для проверки
- `LOG` — путь до файла лога

