# Мониторинг процесса и API (systemd)

скрипт мониторинга и unit-файлы systemd для запуска раз в минуту.


`test_monit.sh` — проверяет процесс `PS_NAME`, фиксирует рестарт (смену PID), пингует `MONIT_URL`, пишет логи в `LOG`.
`systemd/monitoring.service` — oneshot unit, запускает скрипт.
`systemd/monitoring.timer` — таймер, запускает unit каждую минуту.

## Установка на сервере
1) Установить скрипт:
sudo install -m 0755 test_monit.sh /usr/local/bin/test_monit.sh

2) Установить unit-файлы:
sudo install -m 0644 systemd/monitoring.service /etc/systemd/system/monitoring.service
sudo install -m 0644 systemd/monitoring.timer /etc/systemd/system/monitoring.timer

3) Включить и запустить таймер:
sudo systemctl daemon-reload
sudo systemctl enable --now monitoring.timer
sudo systemctl status monitoring.timer


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

