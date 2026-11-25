

#include <iostream>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include <algorithm>
#include <iomanip>
#include <cctype>
#include <cstdlib>
#include <limits>

using namespace std;
=====

const string XOR_KEY = "MySecretKey2024";

string xorEncrypt(const string &data, const string &key) {
    string result = data;
    for (size_t i = 0; i < data.size(); ++i) {
        result[i] = data[i] ^ key[i % key.size()];
    }
    return result;
}

string toHex(const string &data) {
    ostringstream oss;
    for (unsigned char c : data) {
        oss << hex << setw(2) << setfill('0') << (int)c;
    }
    return oss.str();
}

string fromHex(const string &hexStr) {
    string result;
    for (size_t i = 0; i + 1 < hexStr.size(); i += 2) {
        string byteStr = hexStr.substr(i, 2);
        char byte = (char)strtol(byteStr.c_str(), nullptr, 16);
        result += byte;
    }
    return result;
}

string encryptText(const string &plain) {
    return toHex(xorEncrypt(plain, XOR_KEY));
}

string decryptText(const string &cipher) {
    return xorEncrypt(fromHex(cipher), XOR_KEY);
}


struct Entry {
    string site;
    string username;
    string password;
    string note;
};

========================================================

class PasswordManager {
private:
    vector<Entry> entries;
    string filename;

public:
    PasswordManager(const string &file = "vault.dat") : filename(file) {
        load();
    }

  
    void save() {
        ofstream out(filename);
        if (!out) {
            cerr << "[!] Gagal membuka file untuk menyimpan.\n";
            return;
        }
        for (const auto &e : entries) {
            out << e.site << "|"
                << e.username << "|"
                << e.password << "|"
                << e.note << "\n";
        }
        out.close();
        cout << "[+] Data tersimpan (" << entries.size() << " entri).\n";
    }

    void load() {
        entries.clear();
        ifstream in(filename);
        if (!in) return; // file belum ada
        string line;
        while (getline(in, line)) {
            if (line.empty()) continue;
            stringstream ss(line);
            Entry e;
            getline(ss, e.site, '|');
            getline(ss, e.username, '|');
            getline(ss, e.password, '|');
            getline(ss, e.note, '|');
            if (!e.site.empty()) entries.push_back(e);
        }
        in.close();
    }

    // ---------- CRUD ----------
    void addEntry() {
        Entry e;
        cout << "\n--- Tambah Entri ---\n";
        cout << "Situs       : "; getline(cin, e.site);
        cout << "Username    : "; getline(cin, e.username);
        cout << "Password    : "; getline(cin, e.password);
        cout << "Catatan     : "; getline(cin, e.note);

        if (e.site.empty() || e.username.empty() || e.password.empty()) {
            cout << "[!] Situs, username, dan password wajib diisi.\n";
            return;
        }

        e.password = encryptText(e.password);
        entries.push_back(e);
        save();
        cout << "[+] Entri berhasil ditambahkan.\n";
    }

    void listEntries() const {
        cout << "\n--- Daftar Entri (" << entries.size() << ") ---\n";
        if (entries.empty()) {
            cout << "(kosong)\n";
            return;
        }
        cout << left << setw(4) << "No"
             << setw(25) << "Situs"
             << setw(20) << "Username"
             << "Catatan\n";
        cout << string(75, '-') << "\n";
        int idx = 1;
        for (const auto &e : entries) {
            cout << left << setw(4) << idx++
                 << setw(25) << e.site
                 << setw(20) << e.username
                 << e.note << "\n";
        }
    }

    void showPassword(int index) const {
        if (index < 1 || index > (int)entries.size()) {
            cout << "[!] Indeks tidak valid.\n";
            return;
        }
        const Entry &e = entries[index - 1];
        cout << "\nSitus    : " << e.site << "\n";
        cout << "Username : " << e.username << "\n";
        cout << "Password : " << decryptText(e.password) << "\n";
        cout << "Catatan  : " << e.note << "\n";
    }

    void deleteEntry(int index) {
        if (index < 1 || index > (int)entries.size()) {
            cout << "[!] Indeks tidak valid.\n";
            return;
        }
        cout << "[?] Hapus entri '" << entries[index - 1].site << "'? (y/n): ";
        char c; cin >> c; cin.ignore(numeric_limits<streamsize>::max(), '\n');
        if (c == 'y' || c == 'Y') {
            entries.erase(entries.begin() + (index - 1));
            save();
            cout << "[+] Entri dihapus.\n";
        } else {
            cout << "[i] Dibatalkan.\n";
        }
    }

    void searchEntry() const {
        cout << "\n--- Cari Entri ---\n";
        cout << "Kata kunci (situs/username): ";
        string kw; getline(cin, kw);
        if (kw.empty()) return;

        string kwLower = kw;
        transform(kwLower.begin(), kwLower.end(), kwLower.begin(), ::tolower);

        bool found = false;
        cout << "\nHasil pencarian:\n";
        for (size_t i = 0; i < entries.size(); ++i) {
            string siteLower = entries[i].site;
            string userLower = entries[i].username;
            transform(siteLower.begin(), siteLower.end(), siteLower.begin(), ::tolower);
            transform(userLower.begin(), userLower.end(), userLower.begin(), ::tolower);
            if (siteLower.find(kwLower) != string::npos ||
                userLower.find(kwLower) != string::npos) {
                cout << " [" << (i + 1) << "] " << entries[i].site
                     << " | " << entries[i].username << "\n";
                found = true;
            }
        }
        if (!found) cout << "(tidak ditemukan)\n";
    }

    void editEntry(int index) {
        if (index < 1 || index > (int)entries.size()) {
            cout << "[!] Indeks tidak valid.\n";
            return;
        }
        Entry &e = entries[index - 1];
        cout << "\n--- Edit Entri ---\n";
        cout << "Situs baru (kosongkan = tetap): "; string s; getline(cin, s);
        if (!s.empty()) e.site = s;
        cout << "Username baru (kosongkan = tetap): "; string u; getline(cin, u);
        if (!u.empty()) e.username = u;
        cout << "Password baru (kosongkan = tetap): "; string p; getline(cin, p);
        if (!p.empty()) e.password = encryptText(p);
        cout << "Catatan baru (kosongkan = tetap): "; string n; getline(cin, n);
        if (!n.empty()) e.note = n;
        save();
        cout << "[+] Entri diperbarui.\n";
    }

    void stats() const {
        cout << "\n--- Statistik ---\n";
        cout << "Total entri : " << entries.size() << "\n";
        if (entries.empty()) return;

        // Situs unik
        vector<string> sites;
        for (const auto &e : entries) sites.push_back(e.site);
        sort(sites.begin(), sites.end());
        sites.erase(unique(sites.begin(), sites.end()), sites.end());
        cout << "Situs unik  : " << sites.size() << "\n";

        // Panjang password rata-rata (dari plaintext)
        size_t totalLen = 0;
        for (const auto &e : entries) totalLen += decryptText(e.password).size();
        cout << "Rata-rata panjang password: "
             << (totalLen / entries.size()) << " karakter\n";
    }

    // ---------- Menu ----------
    void run() {
        int choice;
        do {
            cout << "\n============================================\n";
            cout << "        PASSWORD MANAAGER ASOYY (CLI)\n";
            cout << "============================================\n";
            cout << " 1. Tambah entri\n";
            cout << " 2. Lihat semua entri\n";
            cout << " 3. Tampilkan password (by index)\n";
            cout << " 4. Cari entri\n";
            cout << " 5. Edit entri\n";
            cout << " 6. Hapus entri\n";
            cout << " 7. Statistik\n";
            cout << " 8. Simpan ulang\n";
            cout << " 0. Keluar\n";
            cout << "Pilihan: ";
            if (!(cin >> choice)) {
                cin.clear();
                cin.ignore(numeric_limits<streamsize>::max(), '\n');
                continue;
            }
            cin.ignore(numeric_limits<streamsize>::max(), '\n');

            switch (choice) {
                case 1: addEntry(); break;
                case 2: listEntries(); break;
                case 3: {
                    listEntries();
                    cout << "Index: "; int i; cin >> i;
                    cin.ignore(numeric_limits<streamsize>::max(), '\n');
                    showPassword(i);
                    break;
                }
                case 4: searchEntry(); break;
                case 5: {
                    listEntries();
                    cout << "Index yang diedit: "; int i; cin >> i;
                    cin.ignore(numeric_limits<streamsize>::max(), '\n');
                    editEntry(i);
                    break;
                }
                case 6: {
                    listEntries();
                    cout << "Index yang dihapus: "; int i; cin >> i;
                    cin.ignore(numeric_limits<streamsize>::max(), '\n');
                    deleteEntry(i);
                    break;
                }
                case 7: stats(); break;
                case 8: save(); break;
                case 0: save(); cout << "Sampai jumpa!\n"; break;
                default: cout << "[!] Pilihan tidak valid.\n";
            }
        } while (choice != 0);
    }
};

===================================================

int main(int argc, char *argv[]) {
    cout << "============================================\n";
    cout << "  Local Password Manager v1.0\n";
    cout << "  (ASOYYYYYYYYYYYYYYY)\n";
    cout << "============================================\n";

    string file = "vault.dat";
    if (argc > 1) file = argv[1];

    PasswordManager pm(file);
    pm.run();

    return 0;
}
